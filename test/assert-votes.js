var conf = rs.conf();
var ret = 0;

for (var i = 0; i < conf["members"].length; i++) {
  member = conf["members"][i];
  if (
      (member.priority !== 1) || (member.votes !== 1)
  ) {
    print("MISCONFIGURED: " + member.host);
    printjson(member);
    ret = 1;
  } else {
    print("OK: " + member.host);
  }
}

quit(ret);
