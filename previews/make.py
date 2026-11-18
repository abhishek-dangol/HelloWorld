icons = {
 'flash': '<path d="M13 2 5 13h5l-1 9 8-12h-5z" fill="#fff"/>',
 'blur': '<circle cx="12" cy="9" r="3.2" fill="#fff"/><path d="M5.5 20c.6-4 3.2-6 6.5-6s5.900 2 6.500 6z" fill="#fff"/>',
 'text': '<path d="M4 6h16M4 10h11M4 14h16M4 18h9" stroke="#fff" stroke-width="2" stroke-linecap="round"/>',
 'wand': '<path d="M5 19 15 9" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/><path d="m17 3 1 2.500 2.500 1-2.500 1-1 2.500-1-2.500-2.500-1 2.500-1z" fill="#fff"/>',
 'filter': '<circle cx="9" cy="10" r="5" fill="none" stroke="#fff" stroke-width="1.800"/><circle cx="15" cy="10" r="5" fill="none" stroke="#fff" stroke-width="1.800"/><circle cx="12" cy="15" r="5" fill="none" stroke="#fff" stroke-width="1.800"/>',
 'gear': '<circle cx="12" cy="12" r="3.200" fill="none" stroke="#fff" stroke-width="2"/><circle cx="12" cy="12" r="7.500" fill="none" stroke="#fff" stroke-width="2.600" stroke-dasharray="3.100 2.800"/>',
}
order = ['flash','blur','text','wand','filter','gear']
def btn(k): return f'<div class="gb"><svg viewBox="0 0 24 24" width="17" height="17">{icons[k]}</svg></div>'
pill = '<span class="pill"><b>4K</b><i>·</i><b>30</b></span>'
def phone(letter, title, where):
    top = ''.join(btn(k) for k in order)
    extra = {'A':'','B':'','C':'','D':'','E':''}
    toprow = f'<div class="top">{top}</div>'
    under = ''; abovezoom=''; byswitch=''; corner=''
    if where=='A': under = f'<div class="under">{pill}</div>'
    if where=='B': toprow = f'<div class="top tight">{top}{pill}</div>'
    if where=='C': abovezoom = f'<div class="abovezoom">{pill}</div>'
    if where=='D': byswitch = f'<div class="byswitch">{pill}</div>'
    if where=='E': corner = f'<div class="corner"><span class="pill stack"><b>4K</b><b>30</b></span></div>'
    return f'''<div class="cell"><div class="cap"><span class="L">{letter}</span>{title}</div>
<div class="ph"><div class="island"></div>{toprow}{under}{corner}
<div class="bottom">{abovezoom}
<div class="zoom"><span>.5</span><span class="on">1x</span><span>2</span><span>4</span><span>8</span></div>
<div class="row"><div class="thumb"></div><div class="shut"><div></div></div><div class="flip"><svg viewBox="0 0 24 24" width="20" height="20"><path d="M5 9a7.500 7.500 0 0 1 13-2.500M19 15a7.500 7.500 0 0 1-13 2.500" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"/><path d="m18 3 .5 4-4 .2M6 21l-.5-4 4-.2" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></div></div>
<div class="modewrap"><div class="mode"><span class="sel">VIDEO</span><span>PHOTO</span></div>{byswitch}</div>
</div></div></div>'''
cells = [('A','Under the top buttons, centred','A'),('B','At the end of the top row','B'),('C','Just above the zoom buttons','C'),('D','Beside the Video / Photo switch','D'),('E','Top right, under the gear','E')]
html = '''<!doctype html><meta charset="utf-8"><style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#111;font-family:-apple-system,"SF Pro Text","Helvetica Neue",Arial,sans-serif;color:#fff;width:1010px;padding:22px 18px 26px}
h1{font-size:25px;font-weight:700;margin:0 0 4px 6px}
p.sub{font-size:16px;color:#bbb;margin:0 0 18px 6px}
.grid{display:flex;flex-wrap:wrap;gap:22px 16px;justify-content:center}
.cell{width:312px}
.cap{font-size:16.500px;font-weight:600;margin:0 0 8px 2px;height:44px;display:flex;align-items:center;gap:9px;line-height:1.200}
.L{flex:none;display:inline-flex;width:34px;height:34px;border-radius:17px;background:#ffd60a;color:#000;font-weight:800;font-size:20px;align-items:center;justify-content:center}
.ph{position:relative;width:312px;height:676px;border-radius:38px;overflow:hidden;border:3px solid #3a3a3c;
 background:radial-gradient(120% 60% at 30% 35%,#8b7a66 0%,#5d5348 38%,#2e2a27 75%,#1b1917 100%)}
.island{position:absolute;top:9px;left:50%;width:92px;height:26px;margin-left:-46px;border-radius:14px;background:#000}
.top{position:absolute;top:48px;left:0;right:0;display:flex;justify-content:space-between;padding:0 16px;align-items:center}
.top.tight{padding:0 10px}
.gb{width:35px;height:35px;border-radius:50%;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center}
.pill{display:inline-flex;align-items:center;gap:5px;height:26px;padding:0 10px;border-radius:13px;background:rgba(0,0,0,.5);font-size:13.500px;font-weight:600;letter-spacing:.3px;box-shadow:0 0 0 2px #ffd60a}
.pill i{font-style:normal;opacity:.7}
.pill b{font-weight:600}
.pill.stack{flex-direction:column;gap:0;height:auto;padding:5px 9px;border-radius:11px;line-height:1.250}
.under{position:absolute;top:93px;left:0;right:0;text-align:center}
.corner{position:absolute;top:93px;right:13px}
.bottom{position:absolute;left:0;right:0;bottom:22px;display:flex;flex-direction:column;align-items:center;gap:13px}
.zoom{display:flex;gap:7px;background:rgba(0,0,0,.35);padding:4px;border-radius:20px}
.zoom span{width:29px;height:29px;border-radius:50%;background:rgba(0,0,0,.45);font-size:11.500px;font-weight:600;display:flex;align-items:center;justify-content:center}
.zoom span.on{width:35px;height:35px;color:#ffd60a;font-size:12.500px}
.row{display:flex;align-items:center;justify-content:space-between;width:100%;padding:0 34px}
.thumb{width:42px;height:42px;border-radius:50%;background:linear-gradient(135deg,#a48b6e,#4d4338);border:1.500px solid #fff}
.shut{width:68px;height:68px;border-radius:50%;border:3.500px solid #fff;display:flex;align-items:center;justify-content:center}
.shut div{width:55px;height:55px;border-radius:50%;background:#ff3b30}
.flip{width:42px;height:42px;border-radius:50%;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center}
.modewrap{position:relative;width:100%;display:flex;justify-content:center}
.mode{display:flex;background:rgba(0,0,0,.45);border-radius:17px;padding:3px;font-size:12px;font-weight:700;letter-spacing:.4px}
.mode span{padding:6px 12px;border-radius:14px}
.mode .sel{background:rgba(255,255,255,.18);color:#ffd60a}
.byswitch{position:absolute;right:16px;top:3px}
</style><h1>Where should the “4K · 30” label go?</h1><p class="sub">Tap “4K” to switch HD / 4K. Tap “30” to switch 30 / 60. The yellow ring is only here to help you spot it.</p><div class="grid">'''
html += ''.join(phone(*c) for c in cells) + '</div>'
open('mock.html','w').write(html)
