import sys, io, base64
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'PlannerRuntime'))
from planner import Planner
from PIL import Image, ImageDraw
p=Planner(sys.argv[1])
apps=[{'id':'com.apple.mail','name':'Mail'},{'id':'com.apple.calculator','name':'Calculator'},{'id':'test.demo','name':'Demo'}]
ctx={'installed_applications':apps,'observation':{'app':'test.demo','name':'Demo','window':'Example','accessibility':True,'truncated':False,'elements':[{'id':'e1','role':'AXButton','label':'Continue','value':'','enabled':True,'editable':False,'actions':['AXPress']}]},'history':[]}
for task in ['Press Continue please','Could you find my Cathay emails?','Bring up my calculator please']:
 action=p.predict(task,ctx)
 print(task,action,flush=True)
 expected={'Press Continue please':'press','Could you find my Cathay emails?':'search_mail','Bring up my calculator please':'open_app'}[task]
 assert action['kind']==expected
ctx['observation']['elements']=[{'id':'e0','role':'AXGroup','label':'Custom canvas','value':'','enabled':True,'editable':False,'actions':[]}]
fallback=p.predict('Press Continue please',ctx)
print('missing AX',fallback,flush=True)
assert fallback['kind']=='vision_observe'
im=Image.new('RGB',(800,500),'white');d=ImageDraw.Draw(im);d.rectangle((500,340,740,440),fill='blue');d.text((565,380),'Continue',fill='white',font_size=32);d.rectangle((60,340,300,440),fill='gray');d.text((120,380),'Cancel',fill='white',font_size=32)
b=io.BytesIO();im.save(b,format='PNG');ctx['observation']['vision']={'id':'screenshot-1','png':base64.b64encode(b.getvalue()).decode()};ctx['history']=[{'action':{'kind':'vision_observe','message':'Custom canvas has no controls'},'result':'Captured current window'}]
a=p.predict('Press Continue please',ctx);print('vision',a,flush=True)
assert a['kind']=='vision_click'
x,y=map(float,a['value'].split(','));assert 625<x<925 and 680<y<880
