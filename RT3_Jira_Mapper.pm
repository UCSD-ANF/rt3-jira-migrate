#!/usr/bin/env perl


package RT3_Jira_Mapper;

use warnings;
use strict;

our @ISA = qw(Exporter);
our @EXPORT = qw( AnonUser setAnonUser mapUser mapPriority mapQueueToProject mapResolution mapCFNames mapCFProc isAnon getRTanonuserlog loadJiraIKMapFile getJiraIssueFromRTTicket getRTTicketFromJiraIssue mapLinkType );

# Modify this to point to the Request Tracker installation location
use lib "/opt/rt3/lib";

# Import RT's API
use RT::Interface::CLI qw(CleanEnv loc);
use RT::Tickets;
use JellyWriter;

# The username to use as the reporter when an RT transaction is from a non-JIRA user
my $_anonuser = "anon";

sub AnonUser {
  return $_anonuser;
}

sub setAnonUser {
  my $uname=shift;
  $_anonuser=$uname if $uname;
}

my %anonuserlog; # List of RT users that are treated as the anonymous user, key is username, value is count

# Map of RT users to Jira users
my %usermap = (
  'rob'           => 'rnewman',
  'rmellors@geology.sdsu.edu' => 'rmellors',
  'lastiz@ucsd.edu' => 'lastiz',
  'RT_System' => 'davis',
  'Nobody' => 'davis',
  'eakins@epicenter.ucsd.edu' => 'eakins',
  'davis@epicenter.ucsd.edu' => 'davis',
  'jeakins@unavco.org' => 'eakins',
  'danny@brtt.com' => 'danny',
  'leyer@ucsd.edu' => 'leyer',
  'pavlis@indiana.edu' => 'pavlis',
  'allan.sauter@gmail.com' => 'sauter',
  'geoff@geoffdavis.com' => 'davis',
  'busby@iris.edu' => 'busby',
  'rnitz@comm-systems.com' => 'rnitz',
  'jkim@sciences.sdsu.edu' => 'jkim',
  'vernon@brtt.com' => 'vernon',
  'davidechavez@gmail.com' => 'dechavez',
  'dchavez@ucsd.edu' => 'dechavez',
  'jbytof@ucsd.edu' => 'jbytof',
  'thim22@gmail.com' => 'thim',
  'dcconstant@ucsd.edu' => 'delia',
  'root' => 'davis',
  'reyes@ucsd.edu' => 'reyes',
  'hafner@iris.edu' => 'hafner',
  'k9pv@sdc.org' => 'k9pv',
  'eakins.jennifer@gmail.com' => 'eakins',
  'judy@ucsd.edu' => 'judy',
  'jdigjudy@gmail.com' => 'judy',
  'tshansen@nlanr.net' => 'tshansen',
  'tshansen@ucsd.edu' => 'tshansen',
  'tshansen@hpwren.ucsd.edu' => 'tshansen',
  'kent' => 'lindquist',
  'clemesha@gmail.com' => 'aclemesh',
  'taimi' => 'tmulder',
  'gulsum' => 'gkarasu',
);

# RT states to Jira resolutions
my %resolutionmap = (
  rejected => "Won't Fix",
  deleted => "Won't Fix",
  resolved => "Fixed",
);

# Map of RT priority numbers to Jira priorities
my %prioritymap = (
  3     =>      "Major",
  2     =>      "Critical",
  4     =>      "Minor",
  1     =>      "Blocker",
  5     =>      "Trivial",
  99    =>      "Blocker",
  0     =>      "Trivial",
  15    =>      "Major",
  10    =>      "Major",
);

my %queuemap = (
  General       => "SYS",
  LACOFD        => "LACOFD",
  ROADNet       => "ROADNET",
  ANZA          => "ANZA",
  SysAdmin      => "SYS",
  webapps       => "WWW",
  Backups       => "BACKUP",
  WebDev        => "WWW",
  USArray       => "TA",
  HiSeasNet     => "HSN",
  PBO           => "PBO",
);

# Map of RT Custom Field names to their Jira names, and a processing function to handle multple values for a field.
# defaults are specifed in the "-default-" record
#
# If no jiraname is specified, it defaults to the RT Field Name
my %cfmap = (
  "Documentation Link" => { 
    jiraname => "Documentation Link", 
    procfunc => \&JellyWriter::multiurl2textfield,
  },
  "Vendor Ticket #" => {
    jiraname => "Vendor Ticket Id",
  },
  "Sat Station" => {
    jiraname => "Satellite Station",
    procfunc => \&JellyWriter::multitext2multiselect,
  },
  Server => {
    jiraname => "Hosts Affected",
  },
  "-default-" => {
    procfunc => \&JellyWriter::multitext2textfield,
  }
);


# Hashes to map jira issue keys to rt tickets
my %jira2rt = ();
my %rt2jira = ();

# Map of rt link types to Jira link types
my %linktypemap = (
  RefersTo => "refers to",
  MemberOf => "is member of",
  DependsOn => "depends on",
);

sub mapLinkType {
  my $linktype=shift;
  return $linktypemap{$linktype};
}

sub mapResolution($){
  my $rtstatus=shift;
  my $res="Fixed";

  $res = $resolutionmap{$rtstatus} if exists $resolutionmap{$rtstatus};
  return $res;
}

# Function to map RT users to Jira users
#
# Since we are not creating new Jira users automatically, any unknown email
# address needs to be mapped to an anonymous user. This mimics the behavior of
# the Jira "Mail Service Handler" with createusers="false" and 
# reporterusername="anon"
# This function expects to get passed an RT::User object
sub mapUser($) {
  my $rtuser=shift; # an RT::User object
  my $name; #bare RT username
  my $jirauser; #username to return

  $name=$rtuser->Name; # Cache the username from the RT::User object
  if ($rtuser->Privileged){
    # If the user is a privileged RT user, we assume the user exists in Jira,
    # rather than returning an anonymous user
    $jirauser=$name;
    # We then check to see if the RT username has been mapped to a different
    # Jira username
    if (exists $usermap{$name}){
      $jirauser=$usermap{$name};
    }
  }
  else {

    # The user is not a privileged RT user
    # but it may be mapped to a real jira user
    # Remap the username if the username is in the map 
    if (exists $usermap{$name}){
      $jirauser=$usermap{$name};
    }
    else {
      # We have an anonymous user. Log it.
      $jirauser=AnonUser();
      $anonuserlog{$name}++;
    }

  }
  return $jirauser;
}


# Function to map RT priorities to Jira Priorities
sub mapPriority($){
  my $priority=shift;
  my $default = "Minor";
  return $default if ($priority eq "");

  if ( exists($prioritymap{$priority}) ){
    $priority = $prioritymap{$priority};
  } else {
    print STDERR "Fallback to Jira priority $default for RT priority $priority\n";
    $priority = $default;
  }
  return $priority;
}

# Map RT Quenename to Jira project Key
sub mapQueueToProject($){
  my $queue=shift;
  my $default="SYS";

  return $default if ($queue eq "");

  if (exists $queuemap{$queue}) {
    $queue=$queuemap{$queue};
  } else {
    print STDERR "Fallback to $default project for RT queue $queue\n";
    $queue=$default;
  }
  return $queue;
}

# Map RT Custom Field Names to Jira Custom Field Names
sub mapCFNames ($) {
  my $field=shift;

  $field=$cfmap{$field}{'jiraname'} if (exists $cfmap{$field}{'jiraname'});

  return $field;
}

# Map RT Custom Fields to a processing function
# returns a reference to a function
sub mapCFProc ($) {
  my $field=shift;

  if (exists $cfmap{$field}{'procfunc'}) {
    return $cfmap{$field}{'procfunc'};
  }
  return $cfmap{'-default-'}{'procfunc'};
}


# isAnon takes a ref to a RT::User object and determines if the user is an anonymous user.
# The following logic applies:
# if RT::User says it's a privileged user in RT, isAnon returns false
# elsif mapUser has an entry for the RTUser that is not $anonuser, isAnon returns false
# else isAnon returns true
sub isAnon($){
  my $rtUser=shift;
  my $name = $rtUser->Name;

  if ($rtUser->Privileged) {
    return 0;
  }
  elsif ( grep (/^$name$/,keys(%usermap))) {
    # user was found in the usermap, so we'll assume it's in Jira
    return 0;
  } 

  # User is anonymous
  # don't log, we'll let mapUser do the logging in anonuserlog
  return 1;
}

# Returns a list of users that were treated as anonymous
sub getRTanonuserlog {
  return keys %anonuserlog;
}

# load a file of jira issues mapped to rt tickets from a file
# file format looks like this:
# JIRA_ISSUE_KEY:RT_TICKET_NUM
#
# for example:
# WWW-33:1759
# WWW-32:1756
# WWW-31:1726
# WWW-30:1725
# WWW-29:1723
sub loadJiraIKMapFile {
  my $fname=shift;
  my ($jira, $rt);
  open DFILE, $fname or die "Can't open issue key map file $fname";
  while (<DFILE>) {
    chomp;
    ($jira,$rt) = split (":", $_);
    $jira2rt{$jira}=$rt;
    $rt2jira{$rt}=$jira;
  }
  close DFILE;
}

sub getJiraIssueFromRTTicket {
  my $rt=shift;
  return $rt2jira{$rt};
}

sub getRTTicketFromJiraIssue {
  my $jira=shift;
  return $jira2rt{$jira};
}

# Module loaded ok
return 1;
