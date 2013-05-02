rt3-jira-migrate
----------------
Geoff Davis <gadavis@ucsd.edu>

This is a set of scripts that read data from a Request Tracker version
3 instance and generate Jira Jelly script output suiteable for importing
data into Jira.

RT3's CSV export capabilities aren't that great, so Jelly script gives
a much greater amount of flexibility in terms of setting dates for
comments and the like.

There is also a script that will make the requisite SOAP API calls to
run individual Jelly scripts on an active Jira instance.

Caveats
-------

* At the time of writing, the JIRA API did not allow a custom closure
  date to be entered for an issue, so all issues in Jira will have their
  import date set as the resolution/closure date.

Requirements
------------

* I believe that user accounts have to be created by hand on the Jira
  instance before the data successfully imports.
* A JIRA custom field to track the original RT3 ticket ID is also required.
