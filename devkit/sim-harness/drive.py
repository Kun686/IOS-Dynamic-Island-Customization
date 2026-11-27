"""启动验证 App 并按时间点截图。

用法: drive.py <模拟器 UDID> <输出目录> <名字> '<环境变量 JSON>' [t1 t2 ...]
不给时间点：启动 2 秒后截一张图（设置页）。
给了时间点：发 go 信号开始时间线，并在这些时刻（相对 go，单位秒）各截一张图。
App 的 NSLog 输出写到 <输出目录>/<名字>.log，里面每个事件后面带着岛当时的状态。
"""
import json, os, subprocess, sys, time
udid, outdir, name, envjson = sys.argv[1:5]
shots = [float(x) for x in sys.argv[5:]]
os.makedirs(outdir, exist_ok=True)
env = dict(os.environ)
for k, v in json.loads(envjson).items():
    env['SIMCTL_CHILD_' + k] = str(v)
def sim(*a, **kw):
    return subprocess.run(['xcrun', 'simctl', *a], env=env, capture_output=True, text=True, **kw)
sim('terminate', udid, 'com.ikharness.app')
logpath = os.path.abspath(os.path.join(outdir, name + '.log'))
r = sim('launch', '--stdout=' + logpath, '--stderr=' + logpath, udid, 'com.ikharness.app')
print('launch:', r.stdout.strip(), r.stderr.strip())
time.sleep(2.0)
if not shots:
    sim('io', udid, 'screenshot', os.path.join(outdir, name + '.png'))
    sys.exit(0)
sim('spawn', udid, 'notifyutil', '-p', 'com.ikharness.go')
t0 = time.time()
for t in shots:
    d = t0 + t - time.time()
    if d > 0: time.sleep(d)
    a = time.time() - t0
    sim('io', udid, 'screenshot', os.path.join(outdir, '%s-%05.1f.png' % (name, t)))
    print('shot %.1f taken at %.2f..%.2f' % (t, a, time.time() - t0))
time.sleep(0.5)
sim('terminate', udid, 'com.ikharness.app')
