# F 核心装配、切换回滚（T008）

## 深读及实际装配

`core-recipe.json`全文；`BundledCore.ets`全文；CoreStore `190–259,329–545`；Types `125–196`；DshHost全文；main `8408–8467,8495–8599,8830–8899`；pack-core `1360–1417`及指定关键函数定位（非5391行全文）；place-host-app `20–117`；dshcompat Endpoints `1–240`仅样本，不能充作223端点全核。

配方当前0.2.2-rc.2+dshm.1；pack-core复制hostcore插件到工作树，profile:770–779插cloud-sync/vm-bash。place-host-app:92–115复制app脚本到hostruntime resfile；已直接重读资源installer失败区与工作树VM对应片段，不只依赖打包脚本注释。未读随包核心zip内字节，实际归档一致性仍是缺口。

## 反证及结论

- BundledCore `338–421`先copy/stage验证再移旧树，commit失败finally恢复stale；不能报“坏新zip必然先删旧树”。CoreStore stage对关键件有哨兵，不等于全树校验。
- DshHost `487–500,574–583`正在运行时切换/回滚只写计划并提示重开，不在同进程直接二次启动；故不能据native Node限制就报“所有切换必崩”。未运行分支仍可start，native重启能力未做运行验证。
- evictionCandidates `162–193`保护current、previous、当前缺失时最新及keepExtra；剔除泛化“所有旧核心被删无法回滚”。
- BundledCore `190–222`以大小stamp判等、缺stamp看builtAt就跳，不能证明内容等同；同版本等长度新容器可能被跳过。这是P2更新识别风险（F-R1），触发需发布同标签等尺寸变更且旧树存在；没有具体本轮新旧容器实例，不能说当前用户已带旧插件。建议内容摘要并验证真实树标识。
- CoreStore writeState `212–223`直接TRUNC，失败可能破坏旧state；尚未官方核验和故障注入，不报确认回滚失败。

## 跨域移交

D-01随资源installer仍在，C-01及C-R2实际核心工作树仍在；没有发现上述位置被pack阶段改写的证据，但未对整个pack脚本或最终zip完成穷举，独立验证应只读归档抽查，不能调用pack。

## 未覆盖

未审所有patch函数/核心模块装配依赖闭包，未完整比对dshcompat实际调用者（当前Web壳主要由上游client调用），未检查凭据/build-profile/签名/已安装私有树。没有构建或运行，不能声称包结构通过或升级在真机通过。
