"""Safety checks for automated release selection, independent of RTL tests."""
from copy import deepcopy
import unittest
from compare_routes import choose, rows


def candidate(route, slack, eligible=True, cls=44000):
    return {'route_option': route, 'eligible': eligible,
            'netlist_sha256': 'same-netlist', 'implementation_inputs': {'rtl/core.v': 'same-source'},
            'worst_setup_slack_ns': slack, 'worst_hold_slack_ns': 0.05,
            'resources': {'CLS': {'used': cls}}, 'bitstream_sha256': f'route{route}'}


class SelectionTests(unittest.TestCase):
    def test_margin_takes_priority_over_resources(self):
        self.assertEqual(choose([candidate(2, 0.1, cls=40000), candidate(1, 0.2, cls=44000)])['selected_route_option'], 1)

    def test_failed_route_cannot_win(self):
        self.assertEqual(choose([candidate(2, 0.1), candidate(1, 10.0, eligible=False)])['selected_route_option'], 2)

    def test_no_pass_means_no_release(self):
        self.assertEqual(choose([candidate(2, -1, False), candidate(1, -2, False)])['status'], 'NO ACCEPTABLE ROUTE')

    def test_netlist_mismatch_stops_selection(self):
        a, b = candidate(2, 0.1), candidate(1, 0.2)
        b['netlist_sha256'] = 'different'
        with self.assertRaises(AssertionError): choose([a, b])

    def test_constraint_mismatch_stops_selection(self):
        a, b = candidate(2, 0.1), candidate(1, 0.2)
        b['implementation_inputs'] = deepcopy(a['implementation_inputs'])
        b['implementation_inputs']['core.sdc'] = 'different-clock'
        with self.assertRaises(AssertionError): choose([a, b])

    def test_negative_slack_cannot_be_eligible(self):
        with self.assertRaises(AssertionError): choose([candidate(2, 0.1), candidate(1, -0.1)])

    def test_exact_tie_uses_device_default(self):
        self.assertEqual(choose([candidate(2, 0.1), candidate(1, 0.1)])['selected_route_option'], 2)

    def test_sta_html_cells(self):
        parsed=list(rows('<tr><td>1</td><td>-0.378</td><td>A&amp;B</td></tr>'))
        self.assertEqual(parsed, [['1', '-0.378', 'A&B']])

    def test_explicit_independent_synthesis_mode(self):
        a,b=candidate(2,0.1),candidate(1,0.2)
        b['netlist_sha256']='independently generated and verified netlist'
        result=choose([a,b],require_same_netlist=False)
        self.assertEqual(result['selected_route_option'],1)
        self.assertEqual(result['comparison_scope'],'SAME_SOURCE_INDEPENDENT_SYNTHESES')

    def test_independent_synthesis_still_requires_identical_inputs(self):
        a,b=candidate(2,0.1),candidate(1,0.2)
        b['netlist_sha256']='different';b['implementation_inputs']['clock.sdc']='different'
        with self.assertRaises(AssertionError): choose([a,b],require_same_netlist=False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
