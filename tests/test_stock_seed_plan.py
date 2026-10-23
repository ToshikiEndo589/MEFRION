from datetime import date
import unittest
from scripts.plan_stock_seed import build_plan


class StockSeedPlanTests(unittest.TestCase):
    def pool(self, count):
        return {kind: [{'asset_id': f'{kind}-{i}', 'species': kind, 'photographer': 'A',
                        'source_page': f'https://www.pexels.com/photo/{i}/'} for i in range(count)]
                for kind in ('dog', 'cat')}

    def test_initial_and_daily_counts_without_reuse(self):
        entries = build_plan(self.pool(80), date(2026, 10, 13), 2)
        self.assertEqual(len(entries), 160)
        self.assertEqual(len({e['asset_id'] for e in entries}), 160)
        self.assertEqual([sum(e['publication_date'] == day for e in entries) for day in
                          ('2026-10-13', '2026-10-14', '2026-10-15')], [100, 30, 30])
        self.assertEqual(len({e['publication_at'] for e in entries}), 70)
        self.assertEqual(entries[100]['publication_at'], '2026-10-14T09:00:00+09:00')
        self.assertTrue(all(e['rights_state'] == 'pending_individual_review' for e in entries))
        self.assertEqual(len({e['pet_profile_key'] for e in entries}), 160)
        self.assertTrue(all(e['pet_name'] and e['display_account'] == e['pet_name'] for e in entries))
        self.assertTrue(all(e['pet_breed'] == '' for e in entries))

    def test_exhaustion_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'not enough'):
            build_plan(self.pool(79), date(2026, 10, 13), 2)


if __name__ == '__main__':
    unittest.main()
