这个目录是「可选」的。想让它少联网下载，可以把下面这个文件放进来：

  1) node-v24.21.0-win-x64.zip
     官方 Node.js 的 Windows 压缩包（约 36MB）。
     来源：https://registry.npmmirror.com/-/binary/node/v24.21.0/node-v24.21.0-win-x64.zip
     放进来后，机器上没有 Node 时就不再联网下载它（仍会校验 sha256）。

文件名要和上面完全一致，否则脚本会当作没放。

注意：
  * 只有这个 Node 压缩包是脚本会自动用的。DSH 本体和它的依赖有几百个 npm 包、
    插件也走 npm，都无法靠这个目录做到完全离线安装。
  * 想离线装插件，可以自己 `npm pack dsh-kb-rag` 拿到 tgz，然后手动执行
    `dsh plugin --profile web add <tgz 的完整路径>`（这是手动路径，脚本不会自动用它）。
