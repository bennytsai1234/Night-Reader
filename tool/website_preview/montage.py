import sys, os
from PIL import Image

d = sys.argv[1]
names = {
    'a': ['hero', 'f1', 'f2', 'f3', 'f4', 'f5', 'more', 'end'],
    'b': ['hero', 's1', 's2', 's3', 's4', 's5', 'more', 'end'],
}
for page in 'ab':
    for scheme in ('light', 'dark'):
        for sz in ('desktop', 'mobile'):
            ims = [Image.open(f'{d}/{page}-{sz}-{scheme}-{n}.png').convert('RGB') for n in names[page]]
            if sz == 'desktop':
                w = 720; cols = 2
            else:
                w = 260; cols = 4
            ims = [im.resize((w, int(im.height * w / im.width))) for im in ims]
            h = ims[0].height
            rows = (len(ims) + cols - 1) // cols
            sheet = Image.new('RGB', (cols * (w + 6), rows * (h + 6)), (40, 40, 40))
            for i, im in enumerate(ims):
                sheet.paste(im, ((i % cols) * (w + 6), (i // cols) * (h + 6)))
            sheet.save(f'{d}/sheet-{page}-{sz}-{scheme}.png')
print('ok')
