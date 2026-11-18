"""Add dialogue/UI glyphs from existing official Noto sources, losing none.

Colour emoji stay on Flutter's normal emoji fallback; source artwork and bank
content are not changed. No fonts or data are downloaded by this build script.
"""
from copy import deepcopy
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.tools/font-build'
OUTPUT = ROOT / 'mobile/assets/fonts'
text = ''.join(p.read_text() for p in (ROOT/'mobile/lib/features/assistant').glob('*.dart'))
requested = {ord(c) for c in text if not c.isspace()}
sources = {
    'DentStudySans-Regular.otf': 'NotoSansCJKsc-Regular.otf',
    'DentStudySans-Bold.otf': 'NotoSansCJKsc-Bold.otf',
    'DentStudySymbols-Regular.ttf': 'NotoSans-Regular.ttf',
    'DentStudyMath-Regular.ttf': 'NotoSansMath-Regular.ttf',
}
coverage = set()
for target_name, source_name in sources.items():
    target = OUTPUT/target_name
    original = TTFont(target)
    existing = set(original.getBestCmap())
    full = TTFont(SOURCE/source_name)
    needed = existing | (requested & set(full.getBestCmap()))
    if needed != existing:
        options = subset.Options()
        options.name_IDs = [0,1,2,3,4,5,6,13,14]
        options.name_legacy = True
        options.name_languages = [0x409]
        builder = subset.Subsetter(options=options)
        builder.populate(unicodes=needed)
        builder.subset(full)
        full['name'] = deepcopy(original['name'])
        if 'CFF ' in full:
            old_cff, new_cff = original['CFF '].cff, full['CFF '].cff
            new_cff.fontNames = list(old_cff.fontNames)
            for key in ('FamilyName','FullName'):
                setattr(new_cff.topDictIndex[0],key,getattr(old_cff.topDictIndex[0],key))
        full.save(target)
    available = set(TTFont(target).getBestCmap())
    assert existing <= available, 'Never remove existing bank/UI glyphs'
    coverage.update(available)
    print(f'{target_name}: +{len(available-existing)} glyphs, {target.stat().st_size} bytes')
missing = requested-coverage
assert missing <= {ord(c) for c in '✨🌱🐳💤🫧🐧☀'}, repr(''.join(map(chr,sorted(missing))))
print('Remaining normal colour-emoji fallback:', ''.join(map(chr,sorted(missing))))
