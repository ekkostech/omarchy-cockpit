const test=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const {spawnSync}=require('node:child_process');
test('real Git scanner handles unusual filenames, published commits and cleanup guards',()=>{
 const script=String.raw`
import runpy,tempfile,pathlib,subprocess,os,json
from unittest.mock import patch
m=runpy.run_path('bin/cockpit-scan')
with tempfile.TemporaryDirectory() as d:
 root=pathlib.Path(d); repo=root/'repo';repo.mkdir();remote=root/'remote.git';wt=root/'task'
 def git(*args):
  p=subprocess.run(['git',*map(str,args)],capture_output=True,text=True)
  assert p.returncode==0,p.stderr
  return p.stdout
 git('init','--bare',remote);git('-C',repo,'init');git('-C',repo,'config','user.email','test@example.invalid');git('-C',repo,'config','user.name','Test')
 (repo/'initial').write_text('a');git('-C',repo,'add','.');git('-C',repo,'commit','-m','initial');git('-C',repo,'remote','add','origin',remote);git('-C',repo,'push','-u','origin','HEAD')
 git('-C',repo,'worktree','add','-b','task',wt)
 records=m['worktree_records'](repo);assert len(records)==2
 w=m['inspect_worktree'](records[1],str(repo));assert w['dirty']==0 and w['published'] and w['statusKnown']
 info={'status':'connected','device':'here','claims':[]}
 m['guard_remove'](str(repo),str(wt),info,[])
 (wt/'line\nwith spaces.txt').write_text('private');files,known,_=m['status_files'](wt);assert known and len(files)==1 and files[0]['path']=='line\nwith spaces.txt'
 try:m['guard_remove'](str(repo),str(wt),info,[]);assert False
 except ValueError as e:assert 'uncommitted' in str(e)
 (wt/'line\nwith spaces.txt').unlink()
 for ci,ts,expected in [({'status':'unavailable','device':'here','claims':[]},[],'unavailable'),({'status':'connected','device':'here','claims':[{'worktree':str(wt),'device':'here','state':'active'}]},[],'agent owns'),(info,[{'cwd':str(wt/'src')}],'terminal')]:
  try:m['guard_remove'](str(repo),str(wt),ci,ts);assert False
  except ValueError as e:assert expected in str(e),str(e)
 git('-C',repo,'worktree','lock',wt)
 try:m['guard_remove'](str(repo),str(wt),info,[]);assert False
 except ValueError as e:assert 'locked' in str(e)
 git('-C',repo,'worktree','unlock',wt)
 (wt/'new').write_text('not pushed');git('-C',wt,'add','.');git('-C',wt,'commit','-m','local only')
 try:m['guard_remove'](str(repo),str(wt),info,[]);assert False
 except ValueError as e:assert 'remote branch' in str(e)
 git('-C',wt,'push','-u','origin','task');m['guard_remove'](str(repo),str(wt),info,[])
 with patch.dict(os.environ,{'XDG_CONFIG_HOME':str(root/'config')}):
  m['action']({'action':'pin','path':str(repo)});m['action']({'action':'root-add','path':str(root)})
  try:m['action']({'action':'root-add','path':''});assert False
  except ValueError as e:assert 'folder path' in str(e)
  cfg=m['settings']();assert cfg['pins']==[str(repo)] and cfg['roots']==[str(root)]
  assert m['config_path']().stat().st_mode & 0o777 == 0o600
  m['action']({'action':'pin','path':str(repo)});assert m['settings']()['pins']==[]
  plugins=root/'config/omarchy/plugins';plugins.mkdir();(plugins/'live.plugin').symlink_to(wt)
  try:m['guard_remove'](str(repo),str(wt),info,[]);assert False
  except ValueError as e:assert 'installed plugin' in str(e)
 git('-C',wt,'mv','initial','renamed file');files,known,_=m['status_files'](wt)
 assert len(files)==1 and files[0]['from']=='initial' and files[0]['path']=='renamed file'
 git('-C',wt,'reset','--hard','HEAD');m['guard_remove'](str(repo),str(wt),info,[]);git('-C',repo,'worktree','remove','--',wt);assert not wt.exists()
 missing=m['inspect_worktree']({'path':str(root/'missing'),'head':'','branch':''},str(repo));assert missing['dirty'] is None and not missing['statusKnown']
print('SCANNER_PASS')
`;
 const r=spawnSync('python3',['-c',script],{cwd:path.join(__dirname,'..'),encoding:'utf8',timeout:20000});
 assert.equal(r.status,0,r.stdout+r.stderr);assert.match(r.stdout,/SCANNER_PASS/);
});
