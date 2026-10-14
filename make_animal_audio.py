"""生成轻量合成动物提示音；不运行在游戏内，可直接替换同名 WAV。"""
from pathlib import Path
import math, random, struct, wave
root=Path(__file__).parent/'audio'
rate=24000
for name in ['chicken_baby','chicken_adult','rabbit_baby','rabbit_adult','pig_baby','pig_adult','grown']:
    rng=random.Random(name)
    duration=0.85 if name=='grown' else (0.72 if 'rabbit' in name else 0.65)
    phase=0.; filtered=0.; frames=[]
    for i in range(int(rate*duration)):
        t=i/rate
        filtered=.74*filtered+.26*rng.uniform(-1,1)
        if name=='grown':
            note=min(2,int(t/.24)); frequency=[523.25,659.25,783.99][note]
            local=t-note*.24
            envelope=min(1,local/.012)*math.exp(-local*9)*(1-t/duration)
            phase+=2*math.pi*frequency/rate
            value=(math.sin(phase)+.15*math.sin(phase*2))*envelope*.34
        elif name.startswith('chicken'):
            period=.19 if name.endswith('baby') else .26
            local=t%period; width=.105 if name.endswith('baby') else .14
            envelope=math.sin(math.pi*min(1,local/width))**2 if local<width else 0
            frequency=(2100+850*math.sin(local/width*math.pi)) if name.endswith('baby') else 330+350*math.exp(-local*18)
            phase+=2*math.pi*frequency/rate
            value=(math.sin(phase)+(.06 if name.endswith('baby') else .35)*math.sin(phase*2))*envelope*.27
        elif name.startswith('rabbit'):
            # 兔子使用轻鼻息/窸窣，避免以尖叫作为日常叫声。
            local=t%.3
            envelope=math.sin(math.pi*min(1,local/.22))**2 if local<.22 else 0
            frequency=720 if name.endswith('baby') else 400
            phase+=2*math.pi*frequency/rate
            value=(filtered*.85+math.sin(phase)*.06)*envelope*.62
        else:
            local=t%.3
            envelope=math.sin(math.pi*min(1,local/.23))**2 if local<.23 else 0
            frequency=(245 if name.endswith('baby') else 110)*(1+.24*math.sin(local*23))
            phase+=2*math.pi*frequency/rate
            value=(math.sin(phase)+.4*math.sin(phase*2)+.2*math.sin(phase*3)+filtered*.25)*envelope*.23
        value*=min(1,t/.01,(duration-t)/.025)
        frames.append(struct.pack('<h',round(max(-.8,min(.8,value))*32767)))
    with wave.open(str(root/f'animal_{name}.wav'),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate);f.writeframes(b''.join(frames))
print('7 animal WAV files generated.')
