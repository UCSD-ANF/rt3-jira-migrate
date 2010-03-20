#!/usr/bin/env python

from suds.client import Client
import getpass, string, sys

outfn = "jira-rt3.out"
username = getpass.getuser()
password = getpass.getpass()

# log in
client = Client('https://anfweb-dev.ucsd.edu/jira/rpc/soap/jirasoapservice-v2?wsdl')
auth = client.service.login(username, password)

# get all customfields on the jira instance and find the one named RT3 Ticket Number
customfields=client.service.getCustomFields(auth)
for cf in customfields:
  if (cf.name == "RT3 Ticket Number"):
    cfid=cf.id




# get all issues with RT3 Ticket Numbers assigned
issues = client.service.getIssuesFromJqlSearch(auth, '"RT3 Ticket Number" is not EMPTY', 99999)

for issue in issues:
  key = issue.key
  for cf in issue.customFieldValues:
    if (cf.customfieldId == cfid):
      vals = cf.values

  print key + ":" + vals[0]


# Log out to be polite
client.service.logout(auth)
