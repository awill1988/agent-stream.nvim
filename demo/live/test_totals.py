import unittest
from totals import sum_positive


class TotalsTest(unittest.TestCase):
    def test_mixed_values(self):
        self.assertEqual(sum_positive([4, -3, 2, 0]), 6)

    def test_non_positive(self):
        self.assertEqual(sum_positive([-5, 0]), 0)

    def test_empty(self):
        self.assertEqual(sum_positive([]), 0)


if __name__ == "__main__":
    unittest.main()
