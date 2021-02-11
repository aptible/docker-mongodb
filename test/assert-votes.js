var conf = rs.conf();
var ret = 0;
var desired_priority = 0;

for (var i = 0; i < conf["members"].length; i++) {

  member = conf["members"][i];

  switch(member.host) {
    case "mongodb-r1:27117":
      desired_priority = 1;
      break;
    default:
      desired_priority = 0.5;
  }


  if (
      (member.priority !== desired_priority) || (member.votes !== 1)
  ) {
    print("MISCONFIGURED: " + member.host);
    printjson(member);
    ret = 1;
  } else {
    print("OK: " + member.host);
  }
}

quit(ret);
