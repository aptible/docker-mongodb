// Expect secondary_name to be set as a variable.
// Unfortunately, this is racy, but it's the best the
// MongoDB docs have to offer :(

var conf = rs.conf();

var member;
for (var i = 0; i < conf["members"].length; i++) {
  member = conf["members"][i];
  if (member.host === secondary_name ) {
    member.priority = 0.5;
    member.votes = 1;
  }
}

var ret = rs.reconfig(conf);

if (ret["ok"] === 1) {
  print("SUCCESS");
} else {
  quit(1);
}
