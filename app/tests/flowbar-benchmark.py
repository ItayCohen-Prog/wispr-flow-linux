#!/usr/bin/env python3
"""Read /proc CPU ticks and RSS during 10-second synthetic preview workloads.
CPU percentages are relative to one core; RSS is not incremental plugin memory.
"""
import os,sys,socket,json,time,math,pathlib
import argparse
parser = argparse.ArgumentParser(description="Measure a disposable Flow Bar preview; sends synthetic events.")
parser.add_argument('--socket', required=True)
parser.add_argument('--shell-pid', required=True, type=int)
parser.add_argument('--compositor-pid', required=True, type=int)
parser.add_argument('--output', required=True, type=pathlib.Path)
args = parser.parse_args()
pids = {'compositor': args.compositor_pid, 'capsule_and_preview': args.shell_pid}
s=socket.socket(socket.AF_UNIX);s.connect(args.socket)
def send(t,p):s.sendall((json.dumps({'t':t,'p':p})+'\n').encode())
def snap():
 out={}
 for n,p in pids.items():
  fields=pathlib.Path('/proc/'+str(p)+'/stat').read_text().rsplit(')',1)[1].split()
  out[n]={'ticks':int(fields[11])+int(fields[12]),'rss_mib':int(fields[21])*os.sysconf('SC_PAGE_SIZE')/1048576}
 return out
results=[]
for stage in ['hidden','notification','listening','processing']:
 send('notification:clear',None);send('status:dictationStatus',stage if stage in ['listening','processing'] else 'idle')
 if stage=='notification':send('notification:show',{'title':'Microphone unavailable','body':'Choose another input device and try again.','timeout':60000,'actions':[{'text':'Try again','callback':'Retry'}]})
 time.sleep(2);before=snap();start=time.monotonic()
 while time.monotonic()-start<10:
  if stage=='listening':send('status:audioLevel',(1+math.sin(time.monotonic()*7))/2)
  time.sleep(1/30)
 elapsed=time.monotonic()-start;after=snap()
 results.append({'stage':stage,'seconds':elapsed,**{n:{'cpu_percent_one_core':round((after[n]['ticks']-before[n]['ticks'])/os.sysconf('SC_CLK_TCK')/elapsed*100,2),'rss_mib':round(after[n]['rss_mib'],1)} for n in pids}})
 args.output.write_text(json.dumps(results,indent=2))
 print(stage,results[-1],flush=True)
send('notification:clear',None);send('status:dictationStatus','idle')
