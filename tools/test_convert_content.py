import unittest
from convert_content import convert, millis

SOURCE = """1
00:00:01,000 --> 00:00:02,500
<i>Merhaba merhaba</i>
العربية:
مرحبًا مرحبًا
الكلمات بالترتيب:
1) Merhaba = مرحبًا.
2) merhaba = مرحبًا.
تعبيرات تساعد على الفهم:
Merhaba = مرحبًا.
المراجع:
https://example.org
"""
class ContentTests(unittest.TestCase):
    def test_preserves_occurrences(self):
        rows,warnings=convert(SOURCE)
        self.assertEqual(len(rows),1)
        self.assertEqual(rows[0]["turkish"],"Merhaba merhaba")
        self.assertEqual(len(rows[0]["words"]),2)
        self.assertNotEqual(rows[0]["words"][0]["id"], rows[0]["words"][1]["id"])
        self.assertEqual(rows[0]["editorialStatus"],"needsReview")
        self.assertEqual(rows[0]["appendix"],["المراجع:","https://example.org"])
    def test_time(self):
        self.assertEqual(millis("01:02:03,004"),3723004)
    def test_reject_invalid(self):
        for source in [SOURCE.replace("00:00:02,500","00:00:00,500"),
                       SOURCE.replace("العربية:",""), SOURCE+SOURCE,
                       SOURCE.replace("2) merhaba","3) merhaba")]:
            with self.subTest(source=source):
                with self.assertRaises(ValueError): convert(source)
    def test_empty(self):
        with self.assertRaises(ValueError): convert("")
if __name__=="__main__": unittest.main()
