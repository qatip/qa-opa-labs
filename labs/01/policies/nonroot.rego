package k8sdemononroot

# Include application, init and ephemeral containers.
all_containers contains container if {
  container := input.review.object.spec.containers[_]
}

all_containers contains container if {
  container := input.review.object.spec.initContainers[_]
}

all_containers contains container if {
  container := input.review.object.spec.ephemeralContainers[_]
}

# A container setting overrides the corresponding Pod setting.
# Missing or null values inherit the Pod setting where available.
effective_setting(container, field) := value if {
  value := container.securityContext[field]
  value != null
} else := value if {
  value := input.review.object.spec.securityContext[field]
  value != null
} else := null

positive_uid(container) if {
  uid := effective_setting(container, "runAsUser")
  is_number(uid)
  uid > 0
}

violation contains {"msg": msg} if {
  some container in all_containers
  effective_setting(container, "runAsNonRoot") != true
  msg := sprintf("Container %q must set runAsNonRoot: true", [container.name])
}

violation contains {"msg": msg} if {
  some container in all_containers
  not positive_uid(container)
  msg := sprintf("Container %q must set runAsUser to a positive UID", [container.name])
}
