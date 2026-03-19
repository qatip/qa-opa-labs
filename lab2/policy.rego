package terraform.aws

# Copy appropriate chunks here


is_delete(rc) if {
  rc.change.actions[_] == "delete"
}