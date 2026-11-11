package k8sdemononroot_test

import data.k8sdemononroot as policy

test_nonroot_accepted if {
  violations := policy.violation with input as data.fixtures.nginx_nonroot
  count(violations) == 0
}

test_root_rejected if {
  violations := policy.violation with input as data.fixtures.nginx_root
  count(violations) == 2
}

test_container_override_rejected if {
  violations := policy.violation with input as data.fixtures.override_root
  count(violations) == 1
}

test_init_root_rejected if {
  violations := policy.violation with input as data.fixtures.init_root
  count(violations) == 1
}

