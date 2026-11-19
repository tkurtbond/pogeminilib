# awk -f doc/mkreadme.awk README.md: README.md with its generated parts
# made afresh, on standard output, run from the top of the repository.
# Between "<!-- program <file> -->" and "<!-- end program -->", the
# program in <file> (examples/readme/), fenced; between "<!-- halt
# codes: ... -->" and "<!-- end halt codes -->", the table in PLAN.md,
# "Halt codes". So the README's programs are the ones the tests build
# and run (TestReadme), and its halt codes are PLAN.md's. awk, not
# python, so `make test` checks it on every host, terhali's included.
/^<!-- program .* -->$/ {
  print
  f = $3
  print "```oberon"
  while ((getline l < f) > 0) print l
  close(f)
  print "```"
  skip = 1; next
}
/^<!-- end program -->$/ { skip = 0 }
/^<!-- halt codes: .* -->$/ {
  print
  intable = 0
  while ((getline l < "PLAN.md") > 0) {
    if (l ~ /^\| Code \| Module \| Meaning \|/) intable = 1
    else if (intable && l !~ /^\|/) break
    if (intable) print l
  }
  close("PLAN.md")
  skip = 1; next
}
/^<!-- end halt codes -->$/ { skip = 0 }
!skip { print }
