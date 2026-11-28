import { getArray, getString } from 'connection';
import type { RpcResult } from 'connection';
import { desktopHostProblem } from './DesktopHostActions';
import type { DesktopHostActions } from './DesktopHostActions';
import { desktopPresetVisible } from './DesktopCodingTools';
import { desktopMenuOptions } from './DesktopMenuOptions';

interface DesktopAgentPresetChoice {
  id: string;
  name?: string;
  description?: string;
}

class DesktopAgentPresetRosterRead {
  expires: number = Number.POSITIVE_INFINITY;
  readonly result: Promise<DesktopAgentPresetChoice[] | undefined>;

  constructor(host: DesktopHostActions) {
    this.result = host.call('agentPresets/list').then((reply: RpcResult): DesktopAgentPresetChoice[] | undefined => {
      this.expires = Date.now() + (reply.ok ? 15000 : 2000);
      if (!reply.ok) { return undefined; }
      const rows: DesktopAgentPresetChoice[] = [];
      for (const item of getArray(reply.value, 'presets') ?? []) {
        const id = getString(item, 'id');
        if (id) { rows.push({ id: id, name: getString(item, 'name'), description: getString(item, 'description') }); }
      }
      return rows;
    }, (): undefined => {
      this.expires = Date.now() + 2000;
      return undefined;
    });
  }
}

const presetRosters = new WeakMap<DesktopHostActions, DesktopAgentPresetRosterRead>();

function readPresetRoster(host: DesktopHostActions): Promise<DesktopAgentPresetChoice[] | undefined> {
  const cached = presetRosters.get(host);
  if (cached !== undefined && cached.expires > Date.now()) { return cached.result; }
  const read = new DesktopAgentPresetRosterRead(host);
  presetRosters.set(host, read);
  return read.result;
}

function displayName(choice: DesktopAgentPresetChoice): ResourceStr {
  if (choice.name !== undefined) { return choice.name; }
  switch (choice.id) {
    case 'standard': return $r('app.string.desktop_agent_preset_standard');
    case 'ptc': return $r('app.string.desktop_agent_preset_ptc');
    case 'minimal': return $r('app.string.desktop_agent_preset_minimal');
    case 'cordis': return $r('app.string.desktop_agent_preset_cordis');
    default: return choice.id;
  }
}

function displayDescription(choice: DesktopAgentPresetChoice): ResourceStr {
  if (choice.name === undefined) {
    switch (choice.id) {
      case 'standard': return $r('app.string.desktop_agent_preset_standard_description');
      case 'ptc': return $r('app.string.desktop_agent_preset_ptc_description');
      case 'minimal': return $r('app.string.desktop_agent_preset_minimal_description');
      case 'cordis': return $r('app.string.desktop_agent_preset_cordis_description');
      default: break;
    }
  }
  return choice.description ?? $r('app.string.desktop_agent_preset_no_description');
}

@Component
export struct DesktopAgentPresetPicker {
  host?: DesktopHostActions;
  @Prop @Watch('sessionChanged') sessionId: string = '';
  @Prop @Watch('projectionChanged') presetId: string = '';
  @Prop @Watch('closeMenu') editable: boolean = false;
  @Prop @Watch('closeMenu') developerTools: boolean = true;
  @State private choices: DesktopAgentPresetChoice[] = [];
  @State private accepted: string = '';
  @State private open: boolean = false;
  @State private busy: boolean = false;
  private active: boolean = false;
  private version: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.version++;
  }

  private sessionChanged(): void {
    this.version++;
    this.accepted = '';
    this.busy = false;
    this.closeMenu();
  }

  private projectionChanged(): void { this.accepted = ''; }

  private closeMenu(): void { this.open = false; }

  private async load(): Promise<void> {
    const host = this.host;
    if (host === undefined) { return; }
    const choices = await readPresetRoster(host);
    if (this.active && this.host === host && choices !== undefined) { this.choices = choices; }
  }

  private currentId(): string { return this.accepted || this.presetId; }

  private currentName(): ResourceStr {
    const id = this.currentId();
    const choice = this.choices.find((row: DesktopAgentPresetChoice): boolean => row.id === id);
    return choice === undefined ? id : displayName(choice);
  }

  private available(): DesktopAgentPresetChoice[] {
    return this.choices.filter((choice: DesktopAgentPresetChoice): boolean =>
      desktopPresetVisible(choice.id, choice.name, this.developerTools));
  }

  private menuOptions(): MenuOptions {
    const options = desktopMenuOptions(Placement.BottomLeft);
    options.onDisappear = (): void => { this.closeMenu(); };
    return options;
  }

  private async select(choice: DesktopAgentPresetChoice): Promise<void> {
    this.closeMenu();
    const host = this.host;
    const owner = this.sessionId;
    if (!owner || !this.active || !this.editable || this.busy || host === undefined || this.currentId() === choice.id ||
        !desktopPresetVisible(choice.id, choice.name, this.developerTools)) { return; }
    this.busy = true;
    const version = ++this.version;
    const reply = await host.call('agentPresets/select', { 'agentId': owner, 'agentPreset': choice.id });
    if (version !== this.version || !this.active || host !== this.host || this.sessionId !== owner) { return; }
    this.busy = false;
    if (reply.ok && typeof reply.value === 'string' && reply.value) {
      this.accepted = reply.value;
    } else {
      const problem = desktopHostProblem(reply);
      this.getUIContext().getPromptAction().showToast({ message: problem ||
        $r('app.string.desktop_agent_preset_selection_failed') });
    }
  }

  @Builder
  private PresetMenu() {
    Menu() {
      ForEach(this.available(), (choice: DesktopAgentPresetChoice): void => {
        MenuItem({ content: displayName(choice), labelInfo: displayDescription(choice) })
          .key('desktopAgentPreset-' + choice.id).selectIcon(true).selected(this.currentId() === choice.id)
          .onChange((): void => { this.select(choice); })
      }, (choice: DesktopAgentPresetChoice): string => choice.id)
    }
  }

  @Builder
  private Caption() {
    Image($r('app.media.dsh_agent_preset_outline')).width(14).height(14).supportSvg2(true)
      .fillColor($r('sys.color.font_secondary')).draggable(false).accessibilityLevel('no')
    Text(this.currentName()).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .fontColor($r('sys.color.font_secondary')).flexShrink(1)
  }

  build() {
    Row() {
      if (this.editable) {
        if (this.choices.length > 0 && this.currentId()) {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 6 }) {
              this.Caption()
              Image($r('app.media.dsh_queue_chevron_down_outline')).width(11).height(11).supportSvg2(true)
                .accessibilityLevel('no')
            }
          }.key('desktopAgentPresetPicker').height(30).padding({ left: 6, right: 6 }).borderRadius(7).focusOnTouch(false)
          .accessibilityGroup(true).accessibilitySelected(this.open)
          .enabled(!this.busy && this.available().length > 0).onClick((): void => {
            this.open = !this.open;
            if (this.open) { this.load(); }
          })
          .bindMenu(this.open, this.PresetMenu, this.menuOptions())
        }
      } else {
        Row({ space: 6 }) { this.Caption() }
          .key('desktopAgentPresetLabel').accessibilityGroup(true)
      }
    }
  }
}
