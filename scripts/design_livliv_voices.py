"""Render the LivLiv voice references locally with Qwen3-TTS VoiceDesign (MLX)."""
import argparse
import json
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1] / "mobile/web/livliv"
# ID, direction, line spoken. The site uses the transcript from the same list.
VOICES = [
    ("p01", "年轻成年女性的清亮高音，音色纤细透亮，轻柔甜美，气息干净，咬字轻巧，带一点笑意", "笔记翻好了。今天也在这里陪着你。"),
    ("p02", "明亮轻巧的少女声，短音节跳跃，有笑意", "分你一口好心情！我们开始吧。"),
    ("p03", "圆润有鼻腔共鸣的卡通嗓音，节奏俏皮，两个拟声词要清楚", "咕咕，嘎嘎！下一题，一起出发。"),
    ("char06", "安静的女中音，气息平稳，声音贴近，吐字轻柔", "书签留在这里。我们慢慢读。"),
    ("char07", "青年男性，清朗自然的男中音，男声胸腔共鸣清楚，明快但沉稳，像年轻男同学", "找到上回那一页了。接着来吧。"),
    ("d01", "细腻柔暖的女声，轻气声，慢半拍，有耐心", "慢慢来，我等你把题读完。"),
    ("d02", "放松的男中低音，带一点沙感，停顿随意", "伸个懒腰。休息好了，再往下看。"),
    ("d03", "元气明亮的女高音，字头清脆，尾音活泼上扬", "来啦！今天也给自己加一分！"),
    ("d03ft", "年轻女声，保留明朗笑意，声音更贴近，语速舒缓自然", "今天也攒下一点进步了。真好。"),
    ("k01", "有舞台感的明亮女中音，开头利落，自信有力", "准备好了？今天也一起闪闪发光。"),
    ("k02", "沉静温润的男低音，胸腔共鸣，字与字之间从容", "把这一题看明白，剩下的交给时间。"),
    ("q02", "柔软圆润的高音，软糯但咬字清晰，速度稍慢", "给你留了一个软软的靠垫。坐吧。"),
    ("q03", "明快的少年男声，中高音，短句，有运动感", "嘿，接住！下一题轮到我们了。"),
    ("s01", "温厚成熟的女中音，气息绵长，口语温和", "喝口水吧。我替你记着这一页。"),
    ("v04", "清朗松弛的青年男声，轻声开口，再自然放开", "吸一口气。好，轻松出发。"),
    ("v05", "略低的女声，丝绒质感，克制而带一点玩笑", "今天的小进步，我可都记着呢。"),
    ("v06", "轻盈带气声的年轻女声，柔和高音，带羞涩的停顿", "嗯，给你一点勇气。我们一起。"),
    ("v07", "明净通透的女声，高音泛音清晰，语句舒展", "抬头看看。今天也有属于你的星光。"),
    ("w01", "结实明快的男中音，像队友打气，节奏干脆", "到我们了！稳住，一题一题来。"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qwen", type=Path, required=True, help="Local MLX Qwen3-TTS VoiceDesign snapshot")
    parser.add_argument("--roles", nargs="+", choices=[role for role, _, _ in VOICES],
                        help="Replace just these roles. By default render missing references.")
    args = parser.parse_args()
    import mlx.core as mx
    from mlx_audio.tts.utils import load_model

    out = ROOT / "voices"
    out.mkdir(exist_ok=True)
    mx.set_cache_limit(128 * 1024 * 1024)
    model = load_model(str(args.qwen))
    for index, (role, direction, line) in enumerate(VOICES):
        dest = out / f"{role}.wav"
        if (args.roles and role not in args.roles) or (not args.roles and dest.exists()):
            continue
        mx.random.seed(20261121 + index)
        (result,) = model.generate_voice_design(
            text=line, language="Chinese", instruct="自然普通话，单人说话。" + direction,
            max_tokens=180,
        )
        audio, rate = np.asarray(result.audio).squeeze(), result.sample_rate
        duration = audio.size / rate
        if not (0.7 < duration < 13 and np.isfinite(audio).all() and np.max(np.abs(audio)) > 0.03):
            raise ValueError(f"Invalid clip for {role}: {duration}s")
        temp = dest.with_suffix(".part.wav")
        sf.write(temp, audio * (.9 / np.max(np.abs(audio))), rate, subtype="PCM_16")
        temp.replace(dest)
        print(f"{role}: {duration:.2f}s", flush=True)
        del audio, result
        mx.clear_cache()
    (out / "lines.json").write_text(json.dumps({k: t for k, _, t in VOICES}, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
