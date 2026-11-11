package k8sdemorequiredlabels_test

import data.k8sdemorequiredlabels as policy

test_missing_owner_rejected if {
  violations := policy.violation with input as data.fixtures.owner_missing
  count(violations) == 1
}

test_owner_present_accepted if {
  violations := policy.violation with input as data.fixtures.owner_present
  count(violations) == 0
}

