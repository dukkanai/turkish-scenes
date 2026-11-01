#!/usr/bin/env python3
"""Convert the extended teaching SRT. Eligibility is editorial, not inferred mastery."""
import argparse, hashlib, html, json, re
from pathlib import Path

HEADER = re.compile(r"(?m)^(\d+)\s*\n(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})\s*\n")
WORD = re.compile(r"^\s*(\d+)\)\s*(.+?)\s*=\s*(.+)$")
def millis(value):
    h,m,s,ms = map(int, re.split("[:,]", value))
    if m > 59 or s > 59: raise ValueError("Invalid timestamp")
    return ((h*60+m)*60+s)*1000+ms
def clean(value):
    return html.unescape(re.sub(r"<[^>]+>", "", value)).strip()
def convert(text):
    matches = list(HEADER.finditer(text))
    if not matches: raise ValueError("No source blocks")
    segments, seen, warnings = [], set(), []
    for i, match in enumerate(matches):
        number = int(match[1])
        if number in seen: raise ValueError("Duplicate source number")
        seen.add(number)
        block = text[match.end():matches[i+1].start() if i+1<len(matches) else len(text)].strip()
        if block.count("العربية:") != 1 or block.count("الكلمات بالترتيب:") != 1:
            raise ValueError(f"Missing/duplicate teaching marker in block {number}")
        turkish, rest = block.split("العربية:", 1)
        arabic, tail = rest.split("الكلمات بالترتيب:", 1)
        words, expressions, appendix = [], [], []
        state = "words"
        for line in tail.splitlines():
            line = line.strip()
            if not line: continue
            found = WORD.match(line) if state == "words" else None
            if found:
                order = int(found[1])
                if order != len(words)+1: raise ValueError(f"Word sequence in block {number}")
                words.append({"id":f"miracle-cell-7:c{number:04}:w{order:02}",
                              "text":clean(found[2]),"explanation":clean(found[3])})
            elif line.startswith("تعبيرات تساعد على الفهم:"):
                state = "expressions"
            elif re.match(r"^(?:المراجع|مراجع|المصادر|مصادر|References|https?://)", line):
                state = "appendix"
                appendix.append(line)
            elif state == "expressions":
                expressions.append(line)
            elif state == "appendix":
                appendix.append(line)
            else:
                # Preserve rather than silently dropping unfamiliar source structure.
                appendix.append(line)
                warnings.append({"segment":number,"reason":"unparsed_word_section_line"})
        start, end = millis(match[2]), millis(match[3])
        if end <= start: raise ValueError(f"Invalid interval in block {number}")
        if segments and start < segments[-1]["startMS"]:
            raise ValueError("Source times out of order")
        if segments and start < segments[-1]["endMS"]:
            warnings.append({"segment":number,"reason":"overlapping_interval"})
        segments.append({"id":f"miracle-cell-7:c{number:04}","number":number,
                         "startMS":start,"endMS":end,"turkish":clean(turkish),
                         "arabic":clean(arabic),"words":words,"expressions":expressions,
                         "editorialStatus":"needsReview","appendix":appendix})
    return segments, warnings

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--source", default="docs/srt/7_Koğuştaki_Mucize.srt")
    ap.add_argument("--output", default="App/Resources/film.json")
    ap.add_argument("--report", default="build/content-report.json")
    args=ap.parse_args()
    source=Path(args.source).read_bytes()
    segments,warnings=convert(source.decode("utf-8-sig"))
    film={"id":"miracle-cell-7","title":"معجزة في الزنزانة رقم 7","youtubeID":"5Xv11SlXPBY",
          "version":1,"sourceSHA256":hashlib.sha256(source).hexdigest(),"segments":segments}
    out=Path(args.output); out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(film,ensure_ascii=False,indent=2)+"\n")
    report=Path(args.report);report.parent.mkdir(parents=True,exist_ok=True)
    report.write_text(json.dumps({"sourceSHA256":film["sourceSHA256"],"segments":len(segments),
        "wordOccurrences":sum(len(s["words"]) for s in segments),"warnings":warnings,
        "linguisticReview":"NOT_RUN","questionBank":"NOT_CREATED"},ensure_ascii=False,indent=2)+"\n")
    print(f"Converted {len(segments)} source blocks; editorial review remains required.")
if __name__=="__main__": main()
