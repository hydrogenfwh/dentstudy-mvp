"""Conservative transcription repairs for the de-identified Wenzhou OCR only.

Not a medical answer generator or a global bank normalizer. Context rules cover
the dental glyph 𬌗; page-specific repairs were checked against rendered source
pages. Ordinary 颌/合, frequency words and anatomical 踝部 remain untouched.
"""
import re

VERSION = 1

# A rare glyph was variously read as 骀/殆 or omitted. Require a dental
# neighbour, rather than replacing those characters in arbitrary prose.
OCCLUSAL_RIGHT = re.compile(
    r'[骀殆](?=面|力|关系|支托|干扰|平面|曲线|颌位|架|龈|楔状隙|方|窝|治疗|'
    r'接触|垫|运|缘|托|堤|关键|创伤|生理|特征|边缘嵴|畸形|与颌位|的最佳自然状态|\s*[（(]occlusion)', re.I)
OCCLUSAL_LEFT = re.compile(
    r'(调|覆|反|锁|开|错|建|偏|超|对刃|侧|前伸|正中|交错|保护|功能|平衡|'
    r'集中|线性|正常|个体|对|息止|组牙|颊|舌|闭|邻|侧向|低|创伤性)[骀殆]')
TERMS = [
    ('错畸形', '错𬌗畸形'),
    ('牙髋', '牙髓'), ('牙隨', '牙髓'),
    ('牙限', '牙龈'), ('卡环臀', '卡环臂'), ('舌例', '舌侧'),
    ('踝状突', '髁状突'), ('踝突', '髁突'), ('盘-踝', '盘-髁'),
    ('𩐿突', '髁突'), ('素乱', '紊乱'),
    ('因索', '因素'),
    ('下颌第一磨牙的面形态', '下颌第一磨牙的𬌗面形态'),
]

# These are source-page transcription patches, not unrestricted synonyms.
# Apply before lexical rules so full-line replacements remain deterministic.
PAGES = {
    23: {'下颌第一磨牙的面形态': '下颌第一磨牙的𬌗面形态',
         '下颌之势位': '下颌姿势位'},
    28: {'前伸时前牙接触': '前伸𬌗时前牙接触',
         '或者轻接触；例': '或者轻接触；侧', '方骀时': '方𬌗时'},
    31: {'浮中颜尖、远中频尖.': '近中颊尖、远中颊尖。',
         '颊洽边缘嵴': '颊𬌗边缘嵴'},
    48: {
        '下领神经及其分艾乌舅外肌关养密奶。该神经电频面乳后即位于翼外肌深面。':
        '下颌神经及其分支与翼外肌关系密切，该神经出卵圆孔后即位于翼外肌深面。',
        '分希于颊部': '分布于颊部',
    },
    69: {'髋底': '髓底', '各根间的又度大': '各根间的叉度大'},
    84: {'间接盖髋术': '间接盖髓术'},
    89: {'唇/频面': '唇/颊面'},
    92: {'顽下颌关节': '颞下颌关节', '穿髋': '穿髓'},
    98: {'董新充填。完全折频车剪底者应拔除。':
         '重新充填。完全折断至髓底者应拔除。'},
    113: {'804以上，因此在採查根管': '80%以上，因此在探查根管',
          '近频': '近颊', '远频': '近颊',
          '串在 60%左右。临床上常連漏': '率在60%左右。临床上常遗漏',
          '幸高，远中根管': '率高，远中根管'},
    115: {'频侧牙齦': '颊侧牙龈'},
    118: {'局限性袭性牙周炎的临床裴现': '局限性侵袭性牙周炎的临床表现'},
    119: {
        '是由牙、牙周膜': '是由牙龈、牙周膜',
        '同时使口腔粘膜与牙体硬组织间是一良好的封闭状态':
        '同时使口腔黏膜与牙体硬组织间呈一良好的封闭状态',
        '2. 牙服（gingiva）：是指盖于牙槽突表面和牙项部周围的口腔咀嚼黏腹，由上皮及下方':
        '2. 牙龈（gingiva）：是指覆盖于牙槽突表面和牙颈部周围的口腔咀嚼黏膜，由上皮及下方',
        '包括游窝龈、附着、绿乳头三部分': '包括游离龈、附着龈、龈乳头三部分',
        '3.游高服（free gingiva）：又称边缘椒，星领圈状包绕牙颈部，宽约1mm。正常粉紅色，':
        '3. 游离龈（free gingiva）：又称边缘龈，呈领圈状包绕牙颈部，宽约1mm。正常呈粉红色，',
        '4.眼沟（gingival sulcus/gingival crevice）：游离限与牙面之同形成的间隙称沟，牙面':
        '4. 龈沟（gingival sulcus/gingival crevice）：游离龈与牙面之间形成的间隙称龈沟，牙面',
        '构成限沟的一，游离限构成限沟的另一璧，用探什可将游离从牙面上分开。限沟的':
        '构成龈沟的一壁，游离龈构成龈沟的另一壁，用探针可将游离龈从牙面上分开。龈沟的',
        '非薄而贴牙面': '菲薄而紧贴牙面', '眼沟的深度': '龈沟的深度',
        '牙曝沟': '牙龈龈沟',
        '是指附于牙槽骨表面的粉红色、坚初': '是指紧附于牙槽骨表面的粉红色、坚韧',
        '附着眼与游离限相连': '附着龈与游离龈相连', '角化限': '角化龈',
        '游高龈凹痕': '游离龈凹痕', '游腐限和附着限': '游离龈和附着龈',
        '牙限裴面': '牙龈表面', '游离限': '游离龈',
        '牙限表面星隆起': '牙龈表面呈隆起',
        '8. 膜龈联合（mucogingival junction）：附著限的根方牙槽貓膜，两者之间有明显的界':
        '8. 膜龈联合（mucogingival junction）：附着龈的根方为牙槽黏膜，两者之间有明显的界',
        '膜蝦联合': '膜龈联合', '牵动唇、频': '牵动唇、颊',
        '膜眼联合': '膜龈联合',
        '娠乳头（gingival papilla）/牙间乳头（interdental papilla）：星锥形充满于相邻两牙接':
        '9. 龈乳头（gingival papilla）/牙间乳头（interdental papilla）：呈锥形充满于相邻两牙接',
        '触区根方的状隙': '触区根方的楔状隙',
        '例面的中央部分': '侧面的中央部分',
        '每个牙的烦、舌侧 乳头': '每个牙的颊、舌侧龈乳头',
        '游离眼的顶部.': '游离龈的顶部，',
        '指牙齿向面方向运动，牙齿在行使功能过程中，面会':
        '指牙齿向𬌗面方向运动，牙齿在行使功能过程中，𬌗面会',
        '为限谷': '为龈谷', '又称限沟上皮': '又称龈沟上皮',
    },
    131: {'检查6个牙（16、11、26、3飽唇频面和36.4日 的舌面）代表全':
          '检查6个牙（16、11、26、31的唇颊面和36、46的舌面）代表全'},
    133: {
        '妥亞統鬆為關程炎症配關者三用 SM过報化區滋櫃萊觀裂并在發内選人抗電消的药執待':
        '对于牙龈有明显炎症的患者，可用3%过氧化氢液冲洗龈袋，并在袋内置入抗菌消炎的药物，待',
    },
    147: {'discoid lupus erythemnatosus': 'discoid lupus erythematosus'},
    160: {'下颌骨状突颈骨折': '下颌骨髁状突颈骨折',
          '影响骨结合的因索': '影响骨结合的因素',
          '变 限。向有哪些': '受限。问有哪些'},
    198: {'对牙列缺 和缺失 者': '对牙列缺损和缺失患者'},
    201: {'由频、舌例': '由颊、舌侧', '前后有快隙': '前后有缺隙',
          '也称为装动轴': '也称为转动轴', '伸向鸦面': '伸向𬌗面',
          '置文托，常用于缺牙多、甚牙条件差或咬合关系差的 例。':
          '置支托，常用于缺牙多、基牙条件差或咬合关系差的病例。',
          '颊面或舌面触点': '颊面或舌面最凸点',
          '观测线验方是非例凹区，观测线倾方': '观测线𬌗方是非倒凹区，观测线龈方',
          '40.|| 型导线：为基牙向峡隙方向倾斜时所画出的导线，基牙上的主要例凹区在近缺隙侧。':
          '40. Ⅱ型导线：为基牙向缺隙方向倾斜时所画出的导线，基牙上的主要倒凹区在近缺隙侧。'},
    234: {
        '为槽与水平面的交角': '为髁槽与水平面的交角',
        '当下颌作前伸运动时》不后牙': '当下颌作前伸运动时，下后牙',
        '（2）侧方干扰的选磨': '（2）侧方𬌗干扰的选磨',
        '工作侧的干扰发生在': '工作侧的𬌗干扰发生在',
        '调磨非支持尖。平衡侧的': '调磨非支持尖。平衡侧的𬌗',
        '（3）前伸干扰的选磨：前伸后牙的干扰发生在':
        '（3）前伸𬌗干扰的选磨：前伸𬌗后牙的𬌗干扰发生在',
        '②保持面形态，避免调磨过度而将人工牙面的牙尖和窝沟形态磨除。':
        '②保持𬌗面形态，避免调磨过度而将人工牙𬌗面的牙尖和窝沟形态磨除。',
        '无骀干扰.则': '无𬌗干扰，则', '存在早接触.则': '存在早接触，则',
        '干扰斜面，。': '干扰斜面。',
    },
    250: {'错畸形': '错𬌗畸形'},
    259: {'（1）能有效地控制矫治牙各个方向的務动。方丝亨新治留能使牙齿作近远中、唇频吉向及':
          '（1）能有效地控制矫治牙各个方向的移动。方丝弓矫治器能使牙齿作近远中、唇颊舌向及'},
    262: {'① 反覆浅者': '① 反覆𬌗浅者', '反覆洽浅者': '反覆𬌗浅者'},
}


def proofread(text, page=None, audit=None):
    def replace(before, after, label):
        nonlocal text
        # A few source omissions are repaired by appending one glyph. Do not
        # append it again when a checked string is processed twice.
        pattern = re.escape(before)
        if after.startswith(before):
            pattern += '(?!' + re.escape(after[len(before):]) + ')'
        text, count = re.subn(pattern, lambda _: after, text)
        if count:
            if audit is not None:
                audit[label] += count

    for before, after in PAGES.get(page, {}).items():
        replace(before, after, f'page:{page}:{before}')
    for before, after in TERMS:
        replace(before, after, f'term:{before}')
    if page == 4:
        text, count = re.subn(r'(?<!棘)层松解', '棘层松解', text)
        if audit is not None and count:
            audit['page:4:层松解'] += count
    # "天然牙随着…" is ordinary prose, not an occurrence of dental pulp.
    text, count = re.subn(r'牙随(?=炎|病|治|温|对|災)', '牙髓', text)
    if audit is not None and count:
        audit['term:牙随(医学语境)'] += count
    for label, pattern, replacement in [
        ('glyph:right', OCCLUSAL_RIGHT, '𬌗'),
        ('glyph:left', OCCLUSAL_LEFT, r'\1𬌗'),
    ]:
        text, count = pattern.subn(replacement, text)
        if audit is not None and count:
            audit[label] += count
    return text
