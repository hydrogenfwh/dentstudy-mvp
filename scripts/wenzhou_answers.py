"""Extract original numbered answer entries and pair only unambiguous headings.

Input must already be de-identified. No generated answers, fuzzy auto-matches,
or invented medical synonym equivalences are permitted.
"""
from collections import defaultdict
import re
import unicodedata
from wenzhou_proofread import proofread

NUMBER = re.compile(r'^\s*(\d{1,3})\s*[.．、，,]\s*(\S.*)$')
CHAPTER = re.compile(r'^(?:第[一二三四五六七八九十百\d]+[章节篇]|【?第[一二三四五六七八九十百\d]+篇|[一二三]+[、.．]\s*(?:名词|简答))')

# Explicitly reviewed wording/OCR correspondences, scoped to one source section.
# These are not a fuzzy-match threshold. In particular no Le Fort numeral,
# incisor/canine, injury/infection, or treatment-scope substitution is allowed.
REVIEWED_HEADINGS = [
    ('感染根管类型和治疗原则', 'WZ-M-088-116', '感染根管的类型和治疗原则'),
    ('感染根管类型治疗原则', 'WZ-M-088-116', '感染根管的类型和治疗原则'),
    ('药物性牙限肥大的定义、病因、临床表现、治疗措施', 'WZ-M-126-146', '药物性牙龈肥大的定义、病因、临床表现、治疗措施'),
    ('依据口腔颌面部的解剖特点简述其损伤特点及其 治疗意义', 'WZ-M-165-196', '依据口腔颌面部的解剖特点简述其损伤的特点及其对治疗的意义'),
    ('错颌畸形的矫治目标', 'WZ-M-250-266', '错畸形的矫治目标'),
    ('下颌下腺导管结石的原因、症状及处理', 'WZ-M-165-196', '下颌下腺导管结石的原因、症状今处理'),
    ('可摘局部义齿不稳定原因处理', 'WZ-M-207-242', '可摘局部义齿不稳定的原因和处理'),
    ('简述方丝弓矫治器的特点和原理', 'WZ-M-250-266', '方丝弓矫治器的特点和基本原理'),
    ('牙隨治疗过程中如何控制感染', 'WZ-M-088-116', '牙髋治疗过程中如何控制感染'),
    ('义齿修复要做哪 外科处理', 'WZ-M-207-242', '义齿修复前要做哪些外科处理'),
    ('腔颌面部良恶性肿瘤的鉴别', 'WZ-M-165-196', '口腔颌面部良恶性肿瘤鉴别'),
    ('口腔颌面部良恶性肿瘤的鉴别', 'WZ-M-165-196', '口腔颌面部良恶性肿瘤鉴别'),
    ('下颌第一磨牙的面形态', 'WZ-M-029-037', '描述下颌第一磨牙的面形态'),
    ('酸蚀冲洗粘接系统的机制', 'WZ-M-088-116', '酸蚀-冲洗粘结系统的机制'),
    ('牙种植体植入术的手术原则', 'WZ-M-165-196', '牙种植体植入术的原则'),
    ('CAD/CAM 基本组成工作原理', 'WZ-M-207-242', 'CAD/CAM的基本组成工作原理、应用'),
    ('牙髓炎（无龋）的鉴别诊断', 'WZ-M-088-116', '牙随炎（无龋）的鉴别诊断'),
    ('RPI 卡环的结构特点及优缺点', 'WZ-M-207-242', 'RPI 卡环组的结构特点和优缺点'),
    ('口颌系统肌链的组成', 'WZ-M-042-051', '简述口颌系统肌链的构成'),
    ('颈内外动脉的鉴别要点', 'WZ-M-042-051', '颈内、外动脉的鉴别'),
    ('影响骨结合的因索和影响种植的颌骨解剖因素', 'WZ-M-165-196', '简述影响种植体骨结合的因索和影响种植手术的颌骨解剖因素'),
    ('腮腺的位置和毗邻', 'WZ-M-042-051', '腮腺的位置、形态和毗邻'),
    ('腮腺的位置、毗邻', 'WZ-M-042-051', '腮腺的位置、形态和毗邻'),
    ('附着烬的定义及意义', 'WZ-M-126-146', '附着龈的定义及意义'),
    ('根管治疗适应症非适应症', 'WZ-M-088-116', '根管治疗术的适应症和非适应症'),
    ('成釉细胞瘤组织学亚型病理表现', 'WZ-M-013-021', '成釉细胞瘤的组织学亚型和各自病理表现'),
    ('Bolten 指数', 'WZ-M-245-249', 'Bolton 指数'),
    ('颞下颌关节成形术原则', 'WZ-M-165-196', '颞下颌关节成形术的手术原则'),
    ('口腔扁平苔藓和口腔白斑的鉴别诊断', 'WZ-M-152-158', '日腔扁平苔藓和口腔白斑的鉴别'),
    ('固定桥修复后出现龈缘炎，牙粘腹炎的原因及处理', 'WZ-M-207-242', '固定桥修复后出现龈缘炎、牙槽嵴黏膜炎的原因及处理'),
    ('局麻药中毒的原因、临床表现、防治原则', 'WZ-M-165-196', '局部麻醉引起中毒的原因、临床表现、防治原则'),
    ('恒牙列期牙列拥挤的矫治原则', 'WZ-M-250-266', '恒牙列期牙列拥挤矫治的基本原则'),
    ('成釉器的发育', 'WZ-M-013-021', '简述成釉器的发育过程'),
    ('四锥形套筒冠优缺点', 'WZ-M-207-242', '圆锥形套筒冠的优缺点'),
    ('釉质发育不全的定义，病因及临床表现', 'WZ-M-088-116', '牙釉质发育不全的定义、病因、临床表现、防治原则'),
    ('根管充填的时机', 'WZ-M-088-116', '根管充填的目的和时机'),
    ('切取活检的注意事项', 'WZ-M-165-196', '简述切取活检的适应症和注意事项'),
    ('复合树脂聚合收缩的概念和影响因素', 'WZ-M-088-116', '复合树脂聚合收缩的定义及影响因素'),
    ('复发性阿弗他溃疡的临床表现', 'WZ-M-152-158', '复发性阿弗他溃疡（RAU）的临床表现和分型'),
    ('牙体龋坏修复原则', 'WZ-M-088-116', '牙体修复的原则'),
    ('牙周手术适应证', 'WZ-M-126-146', '牙周手术的适应症'),
    ('牙体修复原则', 'WZ-M-207-242', '牙体缺损的修复原则'),
    ('固定义齿基牙的选择', 'WZ-M-207-242', '固定义齿的基牙选择要求'),
    ('窝洞的抗力形有哪些？', 'WZ-M-088-116', '简述窝洞的抗力形'),
    ('骨引导膜再生术（GBR）的适用范围', 'WZ-M-165-196', '引导骨再生术（GBR）的原理、适用范围、优点'),
    ('白斑的病因，临床表现，病理改变及癌变倾向', 'WZ-M-152-158', '白斑的病因、病理、临床表现、＜癌变倾向'),
    ('白斑的病因、临床表现、病理改变、恶变倾向', 'WZ-M-152-158', '白斑的病因、病理、临床表现、＜癌变倾向'),
    ('牙脱位后的治疗原理及其处理方法', 'WZ-M-088-116', '牙脱位的治疗原则和处理方法'),
    ('牙限生物型的临床意义', 'WZ-M-126-146', '牙龈生物型的概念和临床意义'),
    ('正畸拔牙的原则', 'WZ-M-250-266', '正畸拔牙矫治的基本原则'),
    ('复合树脂修复体粘接充填失败的原因有哪些', 'WZ-M-088-116', '复合树脂粘接充填失 的原因'),
    ('牙隐裂的病因，临表和防治原则', 'WZ-M-088-116', '牙隐裂的病因、临床表现、诊断要点、防治原则'),
    ('慢性牙周炎主要临床表现', 'WZ-M-126-146', '慢性牙周炎的临床表征'),
    ('乳牙及替牙期局部障碍引起的错颌畸形', 'WZ-M-250-266', '乳牙期及替牙期的局部障碍及造成的错殆畸形'),
    ('早期矫治的优缺点和成功标准', 'WZ-M-250-266', '早期矫治的优缺点（有利/不利因素）及成功标准'),
    ('脓肿切开引流的指征及要求（注意事项）？', 'WZ-M-165-196', '脓肿切开引流的目的、指征、要求（注意事项）及如何建立引流'),
    ('根据全瓷冠的材料和制作工艺分类', 'WZ-M-207-242', '全瓷冠的全瓷材料按照材料和制作工艺的分类'),
    ('干槽症临床表现及处理', 'WZ-M-165-196', '干槽症的临床表现及治疗原则、处理方法'),
    ('牙周病治疗后需要再评估，请问再评估的内容及意义', 'WZ-M-126-146', '牙周基础治疗后再评估的内容及意义'),
    ('舍格伦综合症的病理特征', 'WZ-M-013-021', '舍格伦综合征的病理变化'),
    ('牙列缺失口腔组织支化？', 'WZ-M-207-242', '牙列缺失后的口腔组织改变'),
    ('放射性骨坏死的临床表现和治疗方法', 'WZ-M-165-196', '简述放射性骨坏死的形成机制、临床表现及治疗原则'),
    ('正畸牙移动时牙周组织的变化', 'WZ-M-250-266', '正畸治疗中牙周组织的变化'),
    ('中央型和边缘型颌骨骨髓炎的鉴别', 'WZ-M-165-196', '中央性颌骨骨髓炎和边缘性颌骨骨髓炎的鉴别诊断'),
    ('活动期牙周炎病理表现', 'WZ-M-013-021', '活动期牙周的病理变化'),
    ('根管治疗并发症', 'WZ-M-088-116', '根管治疗的并发症及处理方法'),
    ('天疱疮分型特点', 'WZ-M-152-158', '天疱疮的临床分型和各型特点'),
    ('乳牙X线片检查中注意观察哪些内容', 'WZ-M-069-077', '乳牙牙随病或者根尖周病应该从×线片检查中注意观察哪些内容'),
    ('牙周炎牙槽骨吸收的主要形式', 'WZ-M-126-146', '牙槽骨破坏吸收的形式'),
    ('口颌面部损伤造成窒息的原因', 'WZ-M-165-196', '试述口腔颌面部损伤发生窒息的原因及急救处理'),
    ('棘层松解', 'WZ-M-006-012', '辣层松解（acantholysis）'),
    ('层松解', 'WZ-M-006-012', '辣层松解（acantholysis）'),
    ('C型根管', 'WZ-M-024-028', 'C形根管（C-shaped root canal）'),
    ('牽张成骨', 'WZ-M-161-164', '牵张成骨 （distraction osteogenesis DO）'),
    ('Osseoingration', 'WZ-M-161-164', '骨结合（osseointegration）'),
    ('颞下合关节强直', 'WZ-M-161-164', '颞下颌关节强直 （ankylosis of temporomandibular joint）'),
    ('唇腭裂综合序列治疗', 'WZ-M-161-164', '唇腭裂多学科综合序列治疗（the cleft lip and palate team approach）'),
    ('路德维西咽峡炎', 'WZ-M-161-164', "路德维希咽峡炎（Ludwig'amgina）"),
    ('颞下颌关节紊乱病', 'WZ-M-161-164', '颞下颌关节素乱病（temporomandibular disorders,TMD）'),
    ('韦格纳肉牙肿', 'WZ-M-148-151', "韦格纳肉芽肿病（wegener's granulomatosis）"),
    ('Rige-Fide 溃疡（李-弗氏溃疡）', 'WZ-M-148-151', 'Riga-Fede 溃疡'),
    ('discoid lupus erythemnatosus , DLE', 'WZ-M-148-151', '盘状红斑狼疮（discoid lupus erythematosus ,DLE）'),
    ('根面平整', 'WZ-M-119-125', '根面平整术 （root planing）'),
    ('创伤 （truma from occlusion）', 'WZ-M-119-125', '骀创伤 （trauma from occlusion）'),
]


def key(text):
    # Apply identical lexical repairs to legacy reviewed aliases and current
    # headings, preserving established answer links after OCR correction.
    text = proofread(text)
    text = unicodedata.normalize('NFKC', text).lower()
    for before, after in [('咬合', '合'), ('牙合', '合'), ('𬌗', '合'), ('骀', '合'), ('殆', '合'), ('齲', '龋')]:
        text = text.replace(before, after)
    text = re.sub(r'^(?:简述|试述|论述|请简述|请说明|简要说明|简要叙述)', '', text)
    return re.sub(r'[^a-z0-9\u4e00-\u9fff]', '', text)


def heading_keys(heading, kind):
    values = {key(heading)}
    if kind == '名词解释':
        # Bilingual labels identify their own aliases; no medical synonym list.
        values.add(key(re.sub(r'[（(].*?[)）]', '', heading)))
        for value in re.findall(r'[（(]([^()（）]+)[)）]', heading):
            if re.search(r'[A-Za-z]{3}|[\u4e00-\u9fff]{2}', value):
                values.add(key(value))
            for alias in re.split(r'[,，;；]', value):
                if re.fullmatch(r'\s*[A-Za-z][A-Za-z0-9 \-]{1,100}\s*', alias):
                    values.add(key(alias))
        for value in re.split(r'[/／]', heading):
            values.add(key(value))
            values.add(key(re.sub(r'[（(].*?[)）]', '', value)))
    return {value for value in values if len(value) >= 2}


def extract_entries(page_lines, subject, subdivision, kind, document_id, known_labels=()):
    entries, current = [], None

    def finish():
        nonlocal current
        if current is None:
            return
        lines = current['lines']
        text = '\n'.join(lines).strip()
        if kind == '名词解释':
            # A wrapped bilingual term can span lines before its colon.
            head = re.split(r'[:：]', ' '.join(lines[:3]), maxsplit=1)[0]
            has_colon = bool(re.search(r'[:：]', ' '.join(lines[:3])))
            if not has_colon or len(head) > 180:
                current = None
                return
        else:
            head = lines[0].rstrip('：:')
            if len(lines) < 2:
                current = None
                return
        if len(text) < len(head) + 8:
            current = None
            return
        entries.append(dict(id=f'{document_id}-A-{len(entries) + 1:03}',
                            subject=subject, subdivision=subdivision, kind=kind,
                            heading=head, text=text, sourcePages=sorted(set(current['pages'])),
                            sourceDocumentId=document_id,
                            headingKeys=sorted(heading_keys(head, kind))))
        current = None

    for page, lines in page_lines:
        for line in lines:
            line = line.strip()
            if not line or CHAPTER.match(line) or line in {subject, f'{subject}（{subdivision}）'}:
                continue
            numbered = NUMBER.match(line)
            # Recover an unnumbered bilingual definition only when its label
            # is explicit. Do not treat arbitrary answer prose as a new entry.
            unnumbered = kind == '名词解释' and bool(re.match(
                r'^[^:：。！？]{1,45}[（(][A-Za-z][^:：。！？]{1,90}[)）]\s*[:：]', line))
            if kind == '名词解释' and re.search(r'[:：]', line):
                label = re.split(r'[:：]', line, maxsplit=1)[0]
                if len(label) < 150 and heading_keys(label, kind) & set(known_labels):
                    unnumbered = True
            if numbered or unnumbered:
                finish()
                current = dict(lines=[numbered[2] if numbered else line], pages=[page])
            elif current is not None:
                current['lines'].append(line)
                current['pages'].append(page)
    finish()
    return entries


def attach_answers(items, entries):
    index = defaultdict(list)
    reviewed = defaultdict(list)
    for entry in entries:
        for value in entry['headingKeys']:
            index[entry['subject'], entry['subdivision'], entry['kind'], value].append(entry)
    for source_heading, document_id, answer_heading in REVIEWED_HEADINGS:
        for entry in entries:
            if entry['sourceDocumentId'] == document_id and key(entry['heading']) == key(answer_heading):
                reviewed[entry['subject'], entry['subdivision'], entry['kind'], key(source_heading)].append(entry)
    matched = 0
    for item in items:
        possible = {}
        method = 'exact_heading'
        for value in heading_keys(item['stem'], item['kind']):
            for entry in index.get((item['subject'], item['subdivision'], item['kind'], value), []):
                possible[entry['id']] = entry
        if not possible:
            for entry in reviewed.get((item['subject'], item['subdivision'], item['kind'], key(item['stem'])), []):
                possible[entry['id']] = entry
            method = 'reviewed_heading'
        # Complete identical answers are interchangeable; conflicting versions
        # or several related headings must not be chosen arbitrarily.
        answers = {re.sub(r'\s+', '', entry['text']): entry for entry in possible.values()}
        if len(answers) != 1:
            item.update(answer='', answerSourcePages=[], answerEntryId='',
                        answerMatch='unmatched' if not answers else 'ambiguous')
            continue
        entry = next(iter(answers.values()))
        item.update(answer=entry['text'], answerSourcePages=entry['sourcePages'],
                    answerEntryId=entry['id'], answerMatch=method,
                    answerSourceDocumentId=entry['sourceDocumentId'])
        matched += 1
    return matched
