"""Package a small school catalogue and independently loadable reading bodies.

The canonical audit JSON is retained; runtime navigation never downloads it.
Content-addressed bodies also avoid mixing a cached catalogue with new text.
"""
import argparse
import hashlib
import json
from pathlib import Path

FIELDS = ('id', 'title', 'section', 'subject', 'state', 'sourceFiles',
          'claimedYears', 'courseSupplement', 'sourceAnswersReviewed',
          'mergedRecordIds', 'schoolEvidence', 'sourceLabel', 'continuousQuestions')


def package(canonical):
    payload = json.loads(canonical.read_text())
    directory = canonical.parent / 'school_documents'
    directory.mkdir(parents=True, exist_ok=True)
    schools, count = [], 0
    for school in payload['schools']:
        metadata = {k: v for k, v in school.items() if k != 'documents'}
        documents = []
        for document in school['documents']:
            entry = {k: document[k] for k in FIELDS if k in document}
            body = json.dumps({'id': document['id'], 'text': document.get('text', '')},
                              ensure_ascii=False, separators=(',', ':')).encode()
            entry['hasText'] = bool(document.get('text', '').strip())
            if entry['hasText']:
                filename = hashlib.sha256(body).hexdigest() + '.json'
                (directory / filename).write_bytes(body)
                entry['bodyAsset'] = 'assets/school_documents/' + filename
                count += 1
            documents.append(entry)
        metadata['documents'] = documents
        schools.append(metadata)
    index = canonical.with_name('school_library_index.json')
    index.write_text(json.dumps({'schemaVersion': 2, 'schools': schools},
                                ensure_ascii=False, separators=(',', ':')))
    return {'indexBytes': index.stat().st_size, 'bodyFiles': count,
            'canonicalBytes': canonical.stat().st_size}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('canonical', type=Path)
    args = parser.parse_args()
    print(json.dumps(package(args.canonical)))
