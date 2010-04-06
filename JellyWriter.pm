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
    IssueKeyVarName => "ik",
    IssueKey => undef,

    @_
  );

  $self->{'Filename'} = $args{'Filename'};
  $self->{'IssueKeyVarName'} = $args{'IssueKeyVarName'};
  $self->{'_jellystarted'} = 0;

}

# determine if we should print out an issue key variable or an actual issue key
# Jira Jelly lets you specify a variable name to store the issue key of a
# newly created issue for later key tags.
# This object defaults to using an issue key variable unless an explicit value
# has been specified for the Issue Key
sub _useIssueKeyVar {
  my $self=shift;
  if ( $self->{'IssueKey'} ) {
    return 0;
  } else {
    return 1;
  }
}

sub Writer {
  my $self=shift;
  return $self->{'_writer'};
}

sub _setWriter {
  my $self=shift;
  my $writer=shift;
  $self->{'_writer'}=$writer;
}

sub IssueKeyVarName {
  my $self = shift;
  return $self->{'IssueKeyVarName'};
}

sub setIssueKeyVarName {
  my $self = shift;
  $self->{'IssueKeyVarName'}=shift;
}

sub IssueKey {
  my $self=shift;
  $self->{'IssueKey'};
}

sub setIssueKey {
  my $self=shift;
  my $keyname=shift;
  $self->{'IssueKey'}=$keyname;
}

sub _getWriterKeyVal {
  my $self = shift;
  # check if we should use a variable or issue key
  if ( $self->_useIssueKeyVar() ) {
    return '${'.$self->IssueKeyVarName().'}';
  } else {
    return $self->IssueKey();
  }
}

sub jellyWkFlowStartProgress{
  my $self = shift;
  my $user=shift;
  my @writerparams=(
    workflowAction => 'Start Progress',
  );

  push ( @writerparams, key     => $self->_getWriterKeyVal() );
  push ( @writerparams, user    => $user ) if $user;

  $self->Writer->emptyTag('jira:TransitionWorkflow',@writerparams);

  # Log the user mapping and return
  $users{$user}++ if $user;
}

sub jellyWkFlowStopProgress{
  my $self = shift;
  my $user=shift;
  my @writerparams=(
    workflowAction=> 'Stop Progress',
  );

  push ( @writerparams, key     => $self->_getWriterKeyVal() );
  push ( @writerparams, user    => $user ) if $user;

  $self->Writer->emptyTag('jira:TransitionWorkflow', @writerparams);

  # Log the user mapping and return
  $users{$user}++ if $user;
}

sub jellyWkFlowCloseIssue{
  my $self=shift;
  my $resolution=shift;
  my $user=shift;
  my @writerparams=(
    workflowAction => 'Close Issue',
  );

  push ( @writerparams, key     => $self->_getWriterKeyVal() );
  push ( @writerparams, user    => $user ) if $user;
  push ( @writerparams, resolution => $resolution ) if $resolution;

  $self->Writer->emptyTag('jira:TransitionWorkflow', @writerparams);

  # Log the user mapping and return
  $users{$user}++ if $user;
}

sub jellyWkFlowReopenIssue{
  my $self=shift;
  my $user=shift;

  my @writerparams=(
    workflowAction=>'Reopen Issue',
  );

  push ( @writerparams, key     => $self->_getWriterKeyVal() );
  push ( @writerparams, user    => $user ) if $user;

  $self->Writer->emptyTag('jira:TransitionWorkflow', @writerparams);

  # Log the user mapping and return
  $users{$user}++ if $user;
}

# Output Jira Jelly to create a ticket.
sub jellyStartCreateIssue{
  my $self=shift;

  # check to see if it's ok to create an issue at this point
  if ( $self->{'_inCreateIssueBlock'} ) { 
    die "Can't create an Issue inside of an issue";
  } 

  $self->{'_inCreateIssueBlock'}=1;

  # handle args
  my $issueKeyVar=$self->IssueKeyVarName();
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

  $self->Writer->startTag('jira:CreateIssue', @writerargs);

  # Increment the summary counter for this unique summary
  $summaries{lc($summary)}++;
}

# Output Jira Jelly to close a create ticket block.
sub jellyFinishCreateTicket(){
  my $self=shift;

  # check to see if we should be closing out an issue
  if ( ! $self->{'_inCreateIssueBlock'} ) {
    die "Not in a create issue block";
  }

  $self->Writer->endTag('jira:CreateIssue');
  $self->{'_inCreateIssueBlock'}=0;
}

# Output Jira Jelly Custom Field Value. This must be called within a jellyStartCreateIssue
# and a jellyFinishCreateTicket block
sub jellyAddCustomFieldValue ($$$){
  my $self=shift;
  my $fieldname=shift;
  my $value=shift;

  # check to see if we can write a custom field
  if ( ! $self->{'_inCreateIssueBlock'} ) {
    die "Can't add custom field values outside of a Create Issue block";
  }

  $self->Writer->emptyTag('jira:AddCustomFieldValue',
    name=>$fieldname, value=>$value);
  $customfields{$fieldname}->{$value}++;
}

# Output Jira Jelly to add a comment. Assumes that the issueKeyVar of the previous ticket was set to "key"
sub jellyAddComment {
  my $self=shift;
  my $commenter = shift;
  my $date = shift;
  my $comment = shift;

  # check to see if it's ok to add a comment
  if ( $self->{'_inCreateIssueBlock'} ) {
    die "Can't create a comment inside of a create issue block";
  }
  
  my @writerparams = (
    commenter   => $commenter,
    created     => $date,
    updated     => $date,
    comment     => escapeJellyReservedChars(cleanXML($comment)),
  );

  push ( @writerparams, 'issue-key' => $self->_getWriterKeyVal() );

  $self->Writer->emptyTag('jira:AddComment', @writerparams);
}

# Link Issues
sub jellyLinkIssue {
  my $self = shift;
  my $target = shift;
  my $desc = shift;

  my @writerparams = (
    key => $self->_getWriterKeyVal(),
    linkKey => $target,
    linkDesc => $desc,
  );
  $self->Writer->emptyTag('jira:LinkIssue', @writerparams);
}

sub startJellyOutput ($) {
  my $self = shift;

  die("Trying to startJellyOutput on a file that already has been started",@_) if $self->{'_jellystarted'};
  # Start outputting XML
  $self->{'_output'} = new IO::File( ">" . $self->{'Filename'} );
  $self->_setWriter(new XML::Writer(
    OUTPUT => $self->{'_output'}, 
    ENCODING => 'utf-8',
    #   NEWLINES => 'true',
    DATA_MODE => 'true',
    DATA_INDENT => '2'
  ));

  $self->Writer->xmlDecl();

  # Start Writing Jelly
  $self->Writer->startTag('JiraJelly', 'xmlns:jira' => 'jelly:com.atlassian.jira.jelly.enterprise.JiraTagLib');

  $self->{'_jellystarted'}=1;
  return;
}

sub finishJellyOutput () {
  my $self = shift;

  die ("Trying to finishJellyOutput on a file that is not open", @_) unless $self->{'_jellystarted'};
  # Done with Jelly
  $self->Writer->endTag('JiraJelly');

# Finish outputting XML
  $self->Writer->end();
  $self->{'_output'}->close();

  $self->{'_jellystarted'}=0;
}

sub DESTROY{
  my $self = shift;

  $self->finishJellyOutput() if $self->{'_jellystarted'};
}

# Remove invalid XML unicode characters
# This function ensures that the output string has only valid XML Unicode 
# characters as specified by the XML 1.0 standard. For reference, please 
# see the standard: 
#   http://www.w3.org/TR/REC-xml/#charsets
#
# This function will return an empty string if the input is null or empty.
#
# Solution cobbled together based on this post:
# http://cse-mjmcl.cse.bris.ac.uk/blog/2007/02/14/1171465494443.html
sub cleanXML($) {
  my $input=shift;
  my $output=$input; # string to hold the output
  unless ($input) {
    print STDERR "cleanXML: no input\n";
    return '';
  }

  $output =~ s/[^\x{0009}\x{000A}\x{000D}\x{0020}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]//g;
  #printf STDERR "cleanXML: removed %d chars from input\n", length($input)-length($output);
  return $output;
}

# Additional escapes to remove characters that cause problems with Jelly parsing
sub escapeJellyReservedChars($) {
  $_=shift;
  my $input=$_;

  #s/&/&amp;/g;
  #s/"/&quot;/g;
  #s/</&lt;/g;
  #s/>/&gt;/g;
  #s/\$/&#36;/g;
  s/\${/\$\${/g;
  #s/\*/&#x2a/g;
  #s/\{/&#123/g;
  #s/\}/&#125/g;
  #s/\+/&#43/g;

  return $_;
}

# Combine multiple text values in an array into a single text field, and generate jelly tag only if there are values
# Params:
#  The Jira Field Name
#  A reference to an array containing the RT field values
sub multitext2textfield($$){
  my $self = shift;
  my $jirafieldname = shift;
  my $values_ref = shift;

  $self->jellyAddCustomFieldValue($jirafieldname, join ("\n", @$values_ref)) if scalar @$values_ref;
}

# combine multiple URL entries from an RT CustomField into a single Jira CustomField
sub multiurl2textfield($$){
  my $self = shift;
  my $fieldname = shift; # The Jira Name of the Custom Field
  my $values_ref = shift; # A reference to an array containing values
  my @cleanvals; # array to hold the URLS stripped of their surrounding wikitext markup
  my $finalval; # the value that actually gets put into the Jira Custom Field

  # Don't do anything unless we have values to process
  return unless (scalar @$values_ref > 0) ;

  # Strip off wikitext square braces around URLs
  # There may be multiple lines in the wikitext area so split that up
  foreach my $val (@$values_ref) {
    my @linevals=split (/\n/, $val);
    foreach my $lineval (@linevals) {
      $lineval =~ s/^\[(.*)\]$/$1/;
      push @cleanvals, $lineval;
    }
  }

  $finalval = join ("\n", @cleanvals);
  $self->jellyAddCustomFieldValue($fieldname, $finalval);
}

sub multitext2multiselect($$){
  my $self=shift;
  my $jirafieldname = shift;
  my $values_ref = shift;

  foreach my $val (@$values_ref) {
    $self->jellyAddCustomFieldValue($jirafieldname, $val);
  }
}

# Reporting functions
sub getJiraUsers {
  return keys %users;
}

sub getJiraCustomFieldNames(){
  return keys %customfields;
}

sub getJiraCustomFieldValues($){
  my $fn = shift;

  return keys %{$customfields{$fn}};
}
return 1;
