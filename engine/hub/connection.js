'use strict';
const AriaConnection={
 render(value){
  const connected=value?.status==='connected',waiting=!!value?.waitingForExit,busy=launchBusy;
  $('desktopConnectionStatus').textContent=busy?'正在启动并连接…':connected?'换肤服务已连接':waiting?'等待桌面端退出后连接':value?.status==='unconnected'?'桌面端已运行 · 尚未连接':'桌面端尚未打开';
  $('desktopConnectLabel').textContent=busy?'正在连接…':connected?'打开桌面 ChatGPT':waiting?'继续等待连接':'打开并连接桌面端';
  $('launch').innerHTML='<i data-icon="play"></i>'+(busy?'正在连接…':connected?'打开桌面 ChatGPT':'启动并连接桌面端');
  $('desktopConnect').disabled=busy||waiting;icons();
  const show=value?.status==='unconnected'||value?.waitingForExit;
  $('connectionBanner').hidden=!show;
  $('connectionWait').hidden=!!value?.waitingForExit;$('connectionCancel').hidden=!value?.waitingForExit;
  $('connectionTitle').textContent=value?.waitingForExit?'正在等待你保存并退出桌面端':'桌面端已打开，尚未连接换肤';
  $('connectionText').textContent=value?.waitingForExit?'退出后会接续带背景启动，等待期间不会关闭你的窗口。关闭 Aria 或点击取消可结束等待。':'点击“等待退出后连接”，保存工作并自行退出桌面端，Aria 会自动接续启动并连接，无需使用桌面快捷方式。';
 }
};
$('connectionWait').onclick=()=>act('connectAfterExit');
$('connectionCancel').onclick=()=>act('cancelConnect');
