#!/usr/bin/env perl

package JellyWriter;

use warnings;
use strict;

# Need this to make sure we're writing clean XML
use XML::Writer;
use IO::File;

#
# Reporting variables
#
my %users; # List of users that should exist in Jira before import, key is username, value is count
my %customfields; # List of customfields that should exist in Jira before import
my %summaries; # List of summaries - Duplicate summary detection


sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  bless ($self, $class);
  $self->_Init(@_);
  return $self;
}

sub _Init {
  my $self = shift;
  my %args = (
    Filename => undef,
    IssueKey => "ik",

    @_
  );

  $self->{'Filename'} = $args{'Filename'};
  $self->{'IssueKey'} = $args{'IssueKey'};
  $self->{'_jellystarted'} = 0;

}

sub getIssueKey {
  my $self = shift;
  return $self->{'IssueKey'};
}

sub setIssueKey {
  my $self = shift;
  $self->{'IssueKey'}=shift;
}

sub jellyWkFlowStartProgress{
  my $self = shift;
  my $key=$self->getIssueKey();
  my $user=shift;
  my @params=(
    key => '${'.$key.'}',
    workflowAction => 'Start Progress',
  );
  push (@params, user=>$user) if $user;

  $self->{'_writer'}->emptyTag('jira:TransitionWorkflow',@params);

  # Log the user mapping and return
  $users{$user}++ if $user;
}

sub jellyWkFlowStopProgress{
  my $self = shift;
  my $key=$self->getIssueKey();
  my $user=shift;
  my @params=(
    key=>'${'.$key.'}',
    workflowAction=> 'Stop Progress',
  );
  push (@params, user=>$user) if $user;

  $self->{'_writer'}->emptyTag('jira:TransitionWorkflow', @params);

  # Log the user mapping and return
  $users{$user}++ if $user;
}

sub jellyWkFlowCloseIssue{
  my $self=shift;
  my $key=$self->getIssueKey();
  my $resolution=shift;
  my $user=shift;
  my @params=(
    workflowAction => 'Close Issue',
    key => '${'.$key.'}',
  );
  push (@params, user => $user) if $user;
  push (@params, resolution => $resolution) if $resolution;

  $self->{'_writer'}->emptyTag('jira:TransitionWorkflow', @params);

  # Log the user mapping and return
  $users{$user}++ if $user;
}

sub jellyWkFlowReopenIssue{
  my $self=shift;
  my $key=$self->getIssueKey();
  my $user=shift;

  my @params=(
    key=>'${'.$key.'}',
    workflowAction=>'Reopen Issue',
  );

  push (@params, 'user'=>$user) if $user;

  $self->{'_writer'}->emptyTag('jira:TransitionWorkflow', @params);

  # Log the user mapping and return
  $users{$user}++ if $user;
}

# Output Jira Jelly to create a ticket.
sub jellyStartCreateIssue{
  my $self=shift;
  my $issueKeyVar=$self->getIssueKey();
  my $projkey=shift;
  my $summary=shift;
  my $priority=shift;
  my $reporter=shift;
  my $assignee=shift;
  my $description=shift;
  my $created=shift;
  my $updated=shift;

  my @writerargs = (
    'project-key' => $projkey,
    issueKeyVar => $issueKeyVar,
    summary => $summary,
    priority => $priority,
    reporter => $reporter,
    assignee => $assignee,
    description => $description,
    created => $created,
    updated => $updated,
  );

  # If we've seen this summary before, tell Jira Jelly to ignore this duplicate summary
  # http://confluence.atlassian.com/display/JIRAKB/Not+able+to+create+an+issue+with+the+same+summary+using+Jelly+Script
  if ($summaries{lc($summary)}) {
    push @writerargs, duplicateSummary => "ignore";
  }

  $self->{'_writer'}->startTag('jira:CreateIssue', @writerargs);

  # Increment the summary counter for this unique summary
  $summaries{lc($summary)}++;
}

# Output Jira Jelly to close a create ticket block.
sub jellyFinishCreateTicket(){
  my $self=shift;
  $self->{'_writer'}->endTag('jira:CreateIssue');
}

# Output Jira Jelly Custom Field Value. This must be called within a jellyStartCreateIssue
# and a jellyFinishCreateTicket block
sub jellyAddCustomFieldValue ($$){
  my $self=shift;
  my $fieldname=shift;
  my $value=shift;

  $self->{'_writer'}->emptyTag('jira:AddCustomFieldValue',
    name=>$fieldname, value=>$value);
  $customfields{$fieldname}->{$value}++;
}

# Output Jira Jelly to add a comment. Assumes that the issueKeyVar of the previous ticket was set to "key"
sub jellyAddComment($$$){
  my $self=shift;
  my $key=getIssueKey();
  my $commenter = shift;
  my $date = shift;
  my $comment = shift;

  $self->{'_writer'}->emptyTag('jira:AddComment',
    'issue-key'=>'${'.$key.'}',
    commenter=>$commenter,
    created=>$date,
    updated=>$date,
    comment=>escapeJellyReservedChars(cleanXML($comment)));
}

sub startJellyOutput ($) {
  my $self = shift;

  croak("Trying to startJellyOutput on a file that already has been started",@_) if $self->{'_jellystarted'};
  # Start outputting XML
  $self->{'_output'} = new IO::File( ">" . $self->{'Filename'} );
  $self->{'_writer'} = new XML::Writer(
    OUTPUT => $self->{'_output'}, 
    ENCODING => 'utf-8',
    #   NEWLINES => 'true',
    DATA_MODE => 'true',
    DATA_INDENT => '2'
  );

  $self->{'_writer'}->xmlDecl();

  # Start Writing Jelly
  $self->{'_writer'}->startTag('JiraJelly', 'xmlns:jira' => 'jelly:com.atlassian.jira.jelly.enterprise.JiraTagLib');

  $self->{'_jellystarted'}=1;
  return;
}

sub finishJellyOutput () {
  my $self = shift;

  croak ("Trying to finishJellyOutput on a file that is not open", @_) unless $self->{'_jellystarted'};
  # Done with Jelly
  $self->{'_writer'}->endTag('JiraJelly');

# Finish outputting XML
  $self->{'_writer}'}->end();
  $self->{'_output}'}->close();

  $self->{'_jellystarted'}=0;
}

sub DESTROY{
  my $self = shift;

  $self->finishJellyOutput() if $self->{'_jellystarted'};
}

return 1;
