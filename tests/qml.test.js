const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),{spawnSync}=require('node:child_process');
const shell=process.env.OMARCHY_PATH || '/usr/share/omarchy';
const available=fs.existsSync(path.join(shell,'shell/Commons')) && spawnSync('quickshell',['--version']).status===0;
test('actual Qt dashboard preserves selection and supports filtering, details and persisted pins',{skip:!available},()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'cockpit-qt-'));
 try{
  fs.symlinkSync(path.resolve(__dirname,'..'),path.join(dir,'plugin'));
  for(const name of ['Commons','Ui','services'])fs.symlinkSync(path.join(shell,'shell',name),path.join(dir,name));
  fs.writeFileSync(path.join(dir,'shell.qml'),`
import QtQuick
import Quickshell
import "plugin" as Plugin
ShellRoot {
 Plugin.Cockpit {id:p; function refresh() {} }
 Timer {interval:300;running:true;onTriggered:{
  var w={path:"/tmp/demo",branch:"main",head:"1234567",main:true,statusKnown:true,dirty:0,ahead:0,behind:0,upstream:"origin/main",published:true,lastCommit:1000}
  var w2=Object.assign({},w,{path:"/tmp/demo-task",main:false,branch:"task"})
  var a={path:"/tmp/demo",worktrees:[w,w2],remote:""};var b={path:"/tmp/second",worktrees:[Object.assign({},w,{path:"/tmp/second"})],remote:""}
  var scan={repos:[a,b],terminals:[],claims:[],settings:{pins:[],roots:[]},capabilities:{},now:2000,status:"connected",device:"here"}
  p.consumeScan(scan);p.selectedRepoPath="/tmp/demo";p.selectedWorktreePath="/tmp/demo-task";
  scan.repos.reverse();p.consumeScan(scan);
  if(p.worktree.path!=="/tmp/demo-task")throw new Error("selection jumped")
  p.filter="second";if(p.repos.length!==1 || p.repo.path!=="/tmp/second")throw new Error("filter failed")
  p.filter="";p.mode="pinned";if(p.repos.length!==0)throw new Error("pin filter failed")
  p.mode="all";p.runAction({action:"pin",path:"/tmp/demo"});
 }}
 Timer {interval:1700;running:true;onTriggered:{
  if(p.settings.pins.indexOf("/tmp/demo")<0)throw new Error("pin persistence IPC failed")
  console.log("COCKPIT_QT_PASS");Qt.quit()
 }}
 Timer {interval:5000;running:true;onTriggered:Qt.quit()}
}
`);
  const r=spawnSync('quickshell',['-p',dir],{encoding:'utf8',timeout:10000,env:{...process.env,XDG_CONFIG_HOME:dir}});
  const out=r.stdout+r.stderr;assert.equal(r.status,0,out);assert.match(out,/COCKPIT_QT_PASS/);assert.doesNotMatch(out,/Error:|TypeError:|ReferenceError:|Binding loop|Cannot assign|Unable to assign|is not a type/);
  const stored=JSON.parse(fs.readFileSync(path.join(dir,'omarchy/cockpit.json')));assert.deepEqual(stored.pins,['/tmp/demo']);
 }finally{fs.rmSync(dir,{recursive:true,force:true})}
});
