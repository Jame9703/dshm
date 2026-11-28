import { KeyCode } from '@kit.InputKit';
import { deriveKeyRef } from 'appstate';
import { getArray, getBoolean, getField, getNumber, getString } from 'connection';
import { CREDENTIALS_DESCRIBE_ENDPOINT, CREDENTIALS_UNSET_ENDPOINT, SETTINGS_CONFLICT, SETTINGS_DESCRIBE_ENDPOINT,
  SETTINGS_MUTATE_ENDPOINT } from 'dshcompat';
import { dialogMaterial } from 'platform';
import { DesktopHostActions, desktopHostProblem } from '../desktop/DesktopHostActions';

export interface DesktopModelProviderRemovalTarget {
  provider: string;
  label: string;
  namespace: string;
  path: string[];
  managedRef: string;
  revision: number;
}

function valueAtPath(input: Object | undefined, path: string[]): Object | undefined {
  let value = input;
  for (const part of path) {
    if (value !== undefined && Array.isArray(value)) {
      const wrapped: Record<string, Object> = { 'items': value };
      value = getArray(wrapped, 'items')?.[Number(part)];
    } else {
      value = getField(value, part);
    }
  }
  return value;
}

/** One confirmed deletion. A retry continues after a successful credential removal. */
class DesktopModelProviderRemovalTransaction {
  private credentialChecked: boolean = false;
  private credentialRemoved: boolean = false;
  private routeRequested: boolean = false;

  removedCredential(): boolean { return this.credentialRemoved; }

  async run(host: DesktopHostActions, target: DesktopModelProviderRemovalTarget): Promise<ResourceStr> {
    if (!target.provider || !target.namespace || !target.path.length || target.path.some((part: string): boolean => !part) ||
      !Number.isInteger(target.revision) || target.revision < 0 ||
      (target.managedRef !== '' && target.managedRef !== deriveKeyRef(target.provider))) {
      return $r('app.string.desktop_model_provider_removal_stale');
    }

    const reply = await host.call(SETTINGS_DESCRIBE_ENDPOINT);
    if (!reply.ok) { return desktopHostProblem(reply); }
    const document = getArray(reply.value, 'namespaces')?.find((row: Object): boolean =>
      getString(row, 'ns') === target.namespace);
    if (document === undefined || getBoolean(reply.value, 'writable') !== true) {
      return $r('app.string.desktop_model_provider_removal_unavailable');
    }
    if (valueAtPath(getField(document, 'base'), target.path) !== undefined) {
      return $r('app.string.desktop_model_provider_removal_stale');
    }
    const userValue = valueAtPath(getField(document, 'user'), target.path);
    if (userValue === undefined && this.routeRequested) { return ''; }
    if (userValue === undefined || getNumber(document, 'revision') !== target.revision) {
      return $r('app.string.desktop_model_provider_removal_stale');
    }

    if (target.managedRef && !this.credentialChecked) {
      const profile = valueAtPath(getField(document, 'value'), target.path);
      if (getString(profile, 'apiKeyEnv') !== target.managedRef) {
        return $r('app.string.desktop_model_provider_removal_stale');
      }
      const described = await host.call(CREDENTIALS_DESCRIBE_ENDPOINT, { 'refs': [target.managedRef] });
      if (!described.ok) { return desktopHostProblem(described); }
      const credential = getField(described.value, target.managedRef);
      const configured = getBoolean(credential, 'configured');
      if (configured === undefined || (configured && getBoolean(credential, 'writable') !== true)) {
        return $r('app.string.desktop_model_provider_removal_credential_changed');
      }
      if (configured) {
        const removed = await host.call(CREDENTIALS_UNSET_ENDPOINT, { 'ref': target.managedRef });
        if (!removed.ok) { return desktopHostProblem(removed); }
        this.credentialRemoved = true;
      }
      this.credentialChecked = true;
    }

    // Both endpoints are independent. The fixed revision also protects a profile replaced after preflight.
    const operation: Record<string, Object> = { 'op': 'unset', 'path': target.path };
    this.routeRequested = true;
    const removed = await host.call(SETTINGS_MUTATE_ENDPOINT,
      { 'ns': target.namespace, 'ops': [operation], 'expectedRevision': target.revision });
    if (!removed.ok) {
      return removed.error?.code === SETTINGS_CONFLICT ? $r('app.string.desktop_model_provider_removal_stale') :
        desktopHostProblem(removed);
    }
    return '';
  }
}

@Component
export struct DesktopModelProviderRemoval {
  @Prop target: DesktopModelProviderRemovalTarget;
  host?: DesktopHostActions;
  onClose: (changed: boolean) => void = (_changed: boolean): void => {};
  @State private busy: boolean = false;
  @State private problem: ResourceStr = '';
  private active: boolean = false;
  private finished: boolean = false;
  private dialogId: number = -1;
  private readonly transaction: DesktopModelProviderRemovalTransaction = new DesktopModelProviderRemovalTransaction();

  aboutToAppear(): void {
    this.active = true;
    const target = this.target;
    const confirmed: DesktopModelProviderRemovalTarget = {
      provider: target.provider, label: target.label || target.provider, namespace: target.namespace,
      path: target.path.slice(), managedRef: target.managedRef, revision: target.revision
    };
    this.openDialog(confirmed);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.closeDialog();
  }

  private async openDialog(target: DesktopModelProviderRemovalTarget): Promise<void> {
    const prompt = this.getUIContext().getPromptAction();
    const host = this.host;
    try {
      const material = dialogMaterial();
      const id = await prompt.openCustomDialog({ builder: (): void => { this.Confirmation(target, host); },
        alignment: DialogAlignment.Center, width: 480, cornerRadius: 20, autoCancel: true, systemMaterial: material,
        backgroundColor: material === undefined ? $r('app.color.desktop_settings_surface') : undefined,
        onWillDismiss: (action): void => { if (!this.busy) { action.dismiss(); } },
        onDidDisappear: (): void => {
          this.dialogId = -1;
          if (this.active && !this.finished) { this.finish(false); }
        }
      });
      if (this.active && !this.finished) { this.dialogId = id; }
      else { prompt.closeCustomDialog(id); }
    } catch (_) {
      if (this.active && !this.finished) {
        prompt.showToast({ message: $r('app.string.desktop_model_provider_removal_open_failed') });
        this.finish(false);
      }
    }
  }

  private closeDialog(): void {
    const dialogId = this.dialogId;
    this.dialogId = -1;
    if (dialogId >= 0) { this.getUIContext().getPromptAction().closeCustomDialog(dialogId); }
  }

  private finish(changed: boolean): void {
    this.finished = true;
    this.closeDialog();
    this.onClose(changed);
  }

  private cancel(): void {
    if (this.active && !this.finished && !this.busy) { this.finish(false); }
  }

  private async confirm(target: DesktopModelProviderRemovalTarget, host?: DesktopHostActions): Promise<void> {
    if (!this.active || this.finished || this.busy || host === undefined) { return; }
    this.busy = true;
    this.problem = '';
    try {
      const problem = await this.transaction.run(host, target);
      if (!this.active) { return; }
      if (problem === '') { this.finish(true); }
      else { this.problem = problem; }
    } catch (_) {
      if (this.active) { this.problem = $r('app.string.desktop_model_provider_removal_failed'); }
    } finally {
      if (this.active) { this.busy = false; }
    }
  }

  @Builder
  private Confirmation(target: DesktopModelProviderRemovalTarget, host?: DesktopHostActions) {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Text($r('app.string.desktop_model_provider_removal_title', target.label))
          .fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button({ buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Image($r('app.media.dsh_settings_close')).width(14).height(14).supportSvg2(true).accessibilityLevel('no')
        }.key('desktopModelProviderRemovalClose').width(28).height(28).padding(0)
          .accessibilityText($r('app.string.desktop_model_provider_removal_close'))
          .enabled(!this.busy).onClick((): void => { this.cancel(); })
      }.width('100%')
      Text(target.managedRef ? $r('app.string.desktop_model_provider_removal_description_with_key', target.label) :
        $r('app.string.desktop_model_provider_removal_description', target.label))
        .fontSize(14).lineHeight(22).width('100%')
      if (this.problem !== '' || host === undefined) {
        Text(host === undefined ? $r('app.string.desktop_model_provider_removal_unavailable') : this.problem)
          .key('desktopModelProviderRemovalError').fontSize(13).fontColor($r('app.color.workspace_status_error'))
          .width('100%')
        if (this.transaction.removedCredential()) {
          Text($r('app.string.desktop_model_provider_removal_partial')).fontSize(13)
            .fontColor($r('sys.color.font_secondary')).width('100%')
        }
      }
      Row({ space: 8 }) {
        Button($r('app.string.desktop_model_provider_removal_cancel'), { buttonStyle: ButtonStyleMode.NORMAL })
          .key('desktopModelProviderRemovalCancel').defaultFocus(true).height(36).borderRadius(8)
          .enabled(!this.busy).onClick((): void => { this.cancel(); })
        Button(this.busy ? $r('app.string.desktop_model_provider_removal_deleting', target.label) :
          $r('app.string.desktop_model_provider_removal_confirm', target.label), { buttonStyle: ButtonStyleMode.NORMAL })
          .key('desktopModelProviderRemovalConfirm').height(36).borderRadius(8)
          .fontColor($r('app.color.workspace_status_error')).backgroundColor(Color.Transparent)
          .border({ width: 1, color: $r('app.color.workspace_status_error') })
          .enabled(!this.busy && host !== undefined).onClick((): void => { this.confirm(target, host); })
      }.width('100%').justifyContent(FlexAlign.End)
    }.key('desktopModelProviderRemovalDialog').width('100%').padding(24)
      .onKeyEvent((event: KeyEvent): boolean => {
        if (event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_ESCAPE) { return false; }
        event.stopPropagation();
        this.cancel();
        return true;
      })
  }

  build() {
    Column() {}
  }
}
