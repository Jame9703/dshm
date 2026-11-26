import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const MARK = '/* DSHM_NATIVE_PICKER */';

function replace(source, anchor, replacement, name) {
  const at = source.indexOf(anchor);
  if (at === -1 || source.indexOf(anchor, at + anchor.length) !== -1) {
    throw new Error(`[pack-core] Native picker anchor changed: ${name}`);
  }
  return source.slice(0, at) + replacement + source.slice(at + anchor.length);
}

function mode(source) {
  const body = 'if(!main)return null;const characters=Array.from(label);const stagger=';
  source = replace(source, body, `${MARK}
const dshmPickerAnchor=(0,react.useRef)(null);
const dshmModeMenu=window.__DSHM_NATIVE_PICKERS__?.usePicker(react,main&&ready&&open&&options.length>0,
  ()=>dshmPickerAnchor.current,()=>({rows:options.map(option=>{
    const text=presetDisplayText(option,t);
    return {key:option.id,label:text.name,detail:text.description??t("noDescription"),
      selected:option.id===state.current,disabled:state.busy,run:()=>select(option.id)};
  })}),()=>setOpen(false))??open;
if(!main)return null;const characters=Array.from(label);const stagger=`, 'mode picker');
  source = replace(source, 'Menu,{open:open&&options.length>0,onClose:',
    'Menu,{open:dshmModeMenu&&options.length>0,onClose:', 'mode visibility');
  return replace(source, 'type:`button`,className:AgentPresetSeat_module_css_default.seat,',
    'ref:dshmPickerAnchor,type:`button`,className:AgentPresetSeat_module_css_default.seat,',
    'mode anchor');
}

function workspace(source) {
  const anchor = 'const handleSelect=id=>{if(id===ADD_WORKSPACE){openDirectoryFlow();return}onPick(id)};';
  source = replace(source, anchor, `${anchor}${MARK}
const dshmWorkspaceMenu=window.__DSHM_NATIVE_PICKERS__?.usePicker(react,
  open&&!addIsTheOnlyEntry&&(!menuIsEmpty||workspaceSnapshot.phase==="pending"),
  ()=>anchorRef?.current,()=>({
    search:showSearch?t("picker.search"):"",query,
    empty:t("picker.noResults"),status:workspaceSnapshot.phase==="pending"?t("picker.loading"):"",
    onSearch:setQuery,
    rows:[
      ...matching.map(({id,title,suffix})=>({key:String(id),label:title,detail:suffix,
        selected:id===selectedId,disabled:flowBusy,run:()=>handleSelect(id)})),
      ...addEntries.map(entry=>({key:String(entry.id),label:entry.label,disabled:entry.disabled,
        run:()=>handleSelect(entry.id)}))
    ]
  }),onClose)??open;
`, 'workspace picker');
  source = replace(source, 'Menu,{open:open&&!addIsTheOnlyEntry&&!menuIsEmpty,anchor:null,items',
    'Menu,{open:dshmWorkspaceMenu&&!addIsTheOnlyEntry&&!menuIsEmpty,anchor:null,items', 'workspace visibility');
  return replace(source, '),open&&!addIsTheOnlyEntry&&!menuIsEmpty&&workspaceSnapshot.phase===',
    '),dshmWorkspaceMenu&&!addIsTheOnlyEntry&&!menuIsEmpty&&workspaceSnapshot.phase===', 'workspace loading hint');
}

const modelPage = String.raw`${MARK}
const dshmModelPage=()=>{
  if(pane.kind==="detail")return null;
  if(pane.kind==="root"){
    const rows=[{key:"models",label:t("menu.model"),detail:modelLabel,stay:true,drill:true,run:()=>drill(MODEL_PANE)}];
    if(reasoning!==void 0)rows.push({key:"effort",label:t("menu.effort"),detail:effortLabel,stay:true,drill:true,
      run:()=>drill(EFFORT_PANE)});
    const extensions=renderSlot("conversation.input.model.options",{...controls,openPane:pane=>drill({kind:"detail",pane})});
    if((0,react.Children.count)(extensions)>0)rows.push({key:"extensions",label:t("native.more"),stay:true,
      drill:true,run:fallback=>fallback()});
    return {title:t("menu.aria"),rows};
  }
  const rows=currentChoice===void 0?[]:[{key:"back",label:"‹ "+t("menu.aria"),stay:true,run:()=>back(pane)}];
  if(pane.kind==="effort"){
    for(const level of effortChoices)rows.push({key:level.key,label:level.label,disabled:busy,
      selected:effectiveEffort===level.effort,run:()=>chooseEffort(level.effort)});
    return {title:t("menu.effort"),empty:t("empty.efforts"),rows};
  }
  const diagnostics=[];
  if(state.status==="loading")diagnostics.push(t("status.loading"));
  if(state.error!==null&&lastActionRef.current==="load")diagnostics.push(t("error.action",{message:state.error}));
  for(const failure of state.failures)diagnostics.push(t("warning.groupLoad",{
    name:failure.id==="deepseek-account"?t("provider.account"):failure.name,message:failure.message
  }));
  if(state.error!==null&&lastActionRef.current==="load"||state.failures.length>0){
    rows.push({key:"reload",label:t("action.reload"),stay:true,disabled:busy,run:reload});
  }
  for(const group of filteredGroups)for(const model of group.models){
    rows.push({key:JSON.stringify([group.id,model.id]),label:model.name,group:group.provider.name,
      disabled:busy,selected:state.current?.provider===group.id&&state.current.model===model.id,
      run:()=>choose({provider:group.id,model:model.id})});
  }
  return {title:t("menu.model"),search:showSearch?t("search.placeholder"):"",query,onSearch:changeQuery,
    empty:t(choices.length===0?"empty.models":"search.empty"),status:diagnostics.join("\n"),rows};
};
const dshmModelMenu=window.__DSHM_NATIVE_PICKERS__?.usePicker(react,available&&open,()=>triggerRef.current,
  dshmModelPage,()=>close(true))??open;
if(!available)return null;
`;

function model(source) {
  source = replace(source, 'if(!available)return null;const show=()=>', 'const show=()=>', 'model available guard');
  source = replace(source, 'const onBlur=event=>{if(pane.kind===`detail`',
    'const onBlur=event=>{if(window.__DSHM_NATIVE_PICKERS__?.owns(triggerRef.current))return;if(pane.kind===`detail`',
    'model blur lifecycle');
  const body = 'return(0,react_jsx_runtime.jsxs)(`div`,{ref:rootRef,className:ModelSelect_module_css_default.root';
  source = replace(source, body, modelPage + body, 'model picker');
  source = replace(source, 'open&&(0,react_dom.createPortal)((0,react_jsx_runtime.jsxs)(_deepseek_ai_dsh_client_ui_primitives.MenuSurface,',
    'dshmModelMenu&&(0,react_dom.createPortal)((0,react_jsx_runtime.jsxs)(_deepseek_ai_dsh_client_ui_primitives.MenuSurface,',
    'model visibility');
  source = replace(source, 'const zh={"provider.account":', 'const zh={"native.more":`更多模型选项`,"provider.account":', 'model Chinese label');
  return replace(source, 'const en={"provider.account":', 'const en={"native.more":`More model options`,"provider.account":', 'model English label');
}

export function patchNativeWebPickers(stage, log) {
  for (const [name, patch] of [
    ['agent-preset', mode], ['workspace', workspace], ['model-selection', model]
  ]) {
    const path = join(stage, 'node_modules', '@deepseek-ai', `dsh-client-ui-${name}`, 'lib', 'client.js');
    const source = readFileSync(path, 'utf8');
    if (!source.includes(MARK)) {
      writeFileSync(path, patch(source));
      log(`[pack-core] Native picker: ${name}`);
    }
  }
}
