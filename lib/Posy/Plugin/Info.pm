package Posy::Plugin::Info;
use strict;

=head1 NAME

Posy::Plugin::Info - Posy plugin which gives supplementary entry information.

=head1 VERSION

This describes version B<0.05> of Posy::Plugin::Info.

=cut

our $VERSION = '0.05';

=head1 SYNOPSIS

    @plugins = qw(Posy::Core
	Posy::Plugin::YamlConfig
	...
	Posy::Plugin::Info
	...);
    @actions = qw(
	....
	index_entries
	index_info
	...
	);

=head1 DESCRIPTION

This plugin enables the user to provide supplementary information about each
entry in .info files (in Field:Value format), which are parsed and will set
$info_* flavour variables which can be used in flavour templates.  This plugin
can also be used to sort entries by the .info information fields.

This enables one to create useful summaries of entry contents for use in
category or chrono listings when one does not want to display the whole
entry.  While Posy::Plugin::ShortBody enables one to display just the first
sentence in an entry, the usefulness of that can vary widely depending on
what the first sentence is.  With Posy::Plugin::Info one has much more
control over the summary information.

Even more powerful, the sort-by-info ability enables one to sort entries
on much more significant information than just the date or the filename.
What the information actually I<is> is entirely up to you.

One can optionally pre-cache the info data by adding the 'index_info'
action to the actions list, after the 'index_entries' action.

This plugin requires Posy::Plugin::YamlConfig in order to set the type
information in the info fields.

This plugin replaces the 'sort_entries' action and the 'set_vars' action,
provides an 'index_info' action for pre-caching the info data and provides
an 'info' method for returning the info, if any, related to an entry.

=head2 Configuration

This expects configuration settings in the $self->{config} hash,
which, in the default Posy setup, can be defined in the main "config"
file in the data directory.

=over

=item B<info_sort>

If true, enable sorting on .info information.  (default: false)

=item B<info_type_spec>

Define the info-fields and their types.

    info_type_spec:
      Title:
        type: title
      Order:
        type: number
      Rating:
	type: limited
	values:
	  - G
	  - PG
	  - PG13
	  - R
      Author:
	type: string
      Summary:
	type: text

This gives a list of all the fields, and their types, with possible options.
This is used for both sorting and for other plugins which depend on
this one.  The types are used to determine the kind of comparison
or presentation of the particular field.

=over

=item string

A short string, which needs normal string comparison.  The default.

=item text

A multi-line string, which also uses normal string comparison, but
may need to be presented differently (needing a textarea in a form,
for example).

=item number

Compare as a number.

=item title

The field is a title; compare as if any leading "The" or "A" was not there.

=item limited

A short string which is only allowed a limited number of values.
The "values" part of the definition gives those values.
This is not actually enforced, but can be useful when desiring
to present selectable options.
 
=back

=item B<info_sort_spec>

Define the default order by which the entries will be sorted.

    info_sort_spec:
      order:
        - Author
        - Title
        - Order
      reverse_order:
        Title: 1

The 'order' part of the spec is the order the fields are to be sorted by.
The 'reverse_order' part of the spec defines which fields should be sorted
in reverse order; if the field name is there, with a value of 1/true/on,
then that field is to be sorted in reverse.

If after sorting by the fields, there is still no difference, this will
fall back to sorting by time, name or path, depending on what the
value of the config variable 'sort_type' is.

=item B<info_sort_param>

Defining this parameter enables sorting to be specified with a parameter
in the URL.
(default: '')

    posy.cgi?info_sort=Author;info_sort=Title

=item B<info_sort_param_reverse>

If B<info_sort_param> is defined, this defines the parameter which specifies
what fields are sorted in reverse order.

    posy.cgi?info_sort_reverse=Date

=item B<info_cachefile>

The full name of the file to be used to store the cache.
Most people can just leave this at the default.

=back

=head2 Info Caching Parameters

Info pre-caching is turned on if the 'index_info' action is in the action
list.  Otherwise the info data is cached just as it comes.
This plugin will do reindexing the first time it is run, or
if it detects that there are files in the main file index which
are new.  Full or partial reindexing can be forced by setting the
the following parameters:

=over

=item reindex_all

    /cgi-bin/posy.cgi?reindex_all=1

Does a full reindex of all files in the data_dir directory,
clearing the existing information and starting again.

=item reindex

    /cgi-bin/posy.cgi?reindex=1

Updates information for new files only.

=item reindex_cat

    /cgi-bin/posy.cgi?reindex_cat=stories/buffy

Does an additive reindex of all files under the given category.  Does not
delete files from the index.  Useful to call when you know you've just
updated/added files in a particular category index, and don't want to have
to reindex the whole site.

=item delindex

    /cgi-bin/posy.cgi?delindex=1

Deletes files from the index if they no longer exist.  Useful when you've
deleted files but don't want to have to reindex the whole site.

=back

=cut

=head1 OBJECT METHODS

Documentation for developers and those wishing to write plugins.

=head2 init

Do some initialization; make sure that default config values are set.

=cut
sub init {
    my $self = shift;
    $self->SUPER::init();

    # set defaults
    $self->{config}->{info_sort} = 0
	if (!defined $self->{config}->{info_sort});
    $self->{config}->{info_sort_param} = ''
	if (!defined $self->{config}->{info_sort_param});
    $self->{config}->{info_sort_param_reverse} = 'info_sort_reverse'
	if (!defined $self->{config}->{info_sort_param_reverse});
    $self->{config}->{info_cachefile} ||=
	File::Spec->catfile($self->{state_dir}, 'info.dat');
} # init

=head1 Flow Action Methods

Methods implementing actions.  All such methods expect a
reference to a flow-state hash, and generally will update
either that hash or the object itself, or both in the course
of their running.

=head2 sort_entries

$self->sort_entries($flow_state);

Sort the selected entries (that is, $flow_state->{entries})
If $self->{config}->{info_sort} is true, sorts by .info information
given in $self->{config}->{info_sort_spec}.
Otherwise calls the parent sort method.

=cut
sub sort_entries {
    my $self = shift;
    my $flow_state = shift;

    if ($self->{config}->{info_sort}
	and ($self->{config}->{info_sort_spec}
	or ($self->{config}->{info_sort_param}
	    and $self->param($self->{config}->{info_sort_param}))
	))
    {
	# no point sorting if there's only one
	if (@{$flow_state->{entries}} > 1)
	{
	    my @sort_order;
	    if ($self->{config}->{info_sort_param}
		and $self->param($self->{config}->{info_sort_param}))
	    {
		my (@sort_params) = $self->param($self->{config}->{info_sort_param});
		# only use non-empty values
		foreach my $sp (@sort_params)
		{
		    if ($sp)
		    {
			push @sort_order, $sp;
		    }
		}
	    }
	    else
	    {
		@sort_order = @{$self->{config}->{info_sort_spec}->{order}};
	    }

	    my $id_sort_type = (defined $self->{config}->{sort_type}
			     ? $self->{config}->{sort_type} : 'time_reversed');
	    my $id_sort_time = ($id_sort_type eq 'time');
	    my $id_sort_time_reversed = ($id_sort_type eq 'time_reversed');
	    my $id_sort_name = ($id_sort_type eq 'name');
	    my $id_sort_name_reversed = ($id_sort_type eq 'name_reversed');
	    my $id_sort_path = ($id_sort_type eq 'path');
	    my $id_sort_path_reversed = ($id_sort_type eq 'path_reversed');
	    
	    my %sort_type = ();
	    my %sort_numeric = ();
	    my %sort_reversed = ();
	    # turn the sort stuff into easier-to-get-at
	    foreach my $fn (@sort_order)
	    {
		my $a_sort_type =
		    (
		     (exists
		      $self->{config}->{info_type_spec}->{$fn}->{type}
		      and defined
		      $self->{config}->{info_type_spec}->{$fn}->{type})
		     ? 
		     $self->{config}->{info_type_spec}->{$fn}->{type}
		     : 'string'
		    );
		$sort_type{$fn} = $a_sort_type;
		$sort_numeric{$fn} = ($a_sort_type eq 'number');
		if ($self->{config}->{info_sort_param}
		    and $self->param($self->{config}->{info_sort_param}))
		{
		    my (@rev_param) = 
			$self->param($self->{config}->
				     {info_sort_param_reverse});
		    $sort_reversed{$fn} = 0;
		    foreach my $rfn (@rev_param)
		    {
			if ($rfn eq $fn)
			{
			    $sort_reversed{$fn} = 1;
			    last;
			}
		    }
		}
		else
		{
		    $sort_reversed{$fn} =
			$self->{config}->{info_sort_spec}->{reverse_order}->{$fn};
		}
	    }

	    # pre-cache the actual comparison values
	    my %values = ();
	    foreach my $id (@{$flow_state->{entries}})
	    {
		my %a_info = $self->info($id);
		$values{$id} = {};
		foreach my $fn (@sort_order)
		{
		    if (!defined $a_info{$fn})
		    {
			if ($sort_type{$fn} eq 'number')
			{
			    # sort undefined as zero
			    $values{$id}->{$fn} = 0;
			}
			else # string or text or title
			{
			    # sort undefined as the empty string
			    $values{$id}->{$fn} = '';
			}
		    }
		    else
		    {
			my $a_val = $a_info{$fn};
			if ($sort_type{$fn} eq 'number')
			{
			    $a_val =~ s/\s//g; # remove any spaces
			    # non-numeric data should be compared as zero
			    if (!defined $a_val
				|| !$a_val
				|| $a_val =~ /[^\d.]/)
			    {
				$a_val = 0;
			    }
			}
			elsif ($sort_type{$fn} eq 'title')
			{
			    # remove leading The or A from titles
			    $a_val =~ s/^(The\s+|A\s+)//;
			}
			$a_val = lc($a_val); # ignore case on strings
			$values{$id}->{$fn} = $a_val;
		    }
		}
	    } # for each entry

	    $flow_state->{entries} = [ 
		sort { 
		    my $result = 0;
		    foreach my $fn (@sort_order)
		    {
			my $a_val = $values{$a}->{$fn};
			my $b_val = $values{$b}->{$fn};
			$result =
			    (
			     ($sort_reversed{$fn})
			     ? (
				($sort_numeric{$fn})
				?  ($b_val <=> $a_val)
				: ($b_val cmp $a_val)
			       )
			     : (
				($sort_numeric{$fn})
				?  ($a_val <=> $b_val)
				: ($a_val cmp $b_val)
			       )
			    );
			if ($result != 0)
			{
			    return $result;
			}
		    }
		    # fall back on the original sort
		    if ($result == 0)
		    {
			$result = 
			    ($id_sort_time_reversed
			     ? ($self->{files}->{$b}->{mtime} <=> 
				$self->{files}->{$a}->{mtime})
			     : ($id_sort_time
				? ($self->{files}->{$a}->{mtime} <=> 
				   $self->{files}->{$b}->{mtime})
				: ($id_sort_name
				   ? ($self->{files}->{$a}->{basename} cmp
				      $self->{files}->{$b}->{basename})
				   : ($id_sort_name_reversed
				      ? ($self->{files}->{$b}->{basename} cmp
					 $self->{files}->{$a}->{basename})
				      : ($id_sort_path
					 ? ($a cmp $b)
					 : ($b cmp $a)
					)
				     )
				  )
			       )
			    );
		    }
		    $result;
		} @{$flow_state->{entries}} 
	    ];
	}
    }
    else
    {
	$self->SUPER::sort_entries($flow_state);
    }

    1;	
} # sort_entries

=head2 index_info

Find the info data of the entry files.

Expects $self->{config} and $self->{files} to be set.

=cut

sub index_info {
    my $self = shift;
    my $flow_state = shift;

    my $reindex_all = $self->param('reindex_all');
    $reindex_all = 1 if (!$self->_info_init_caching());
    if (!$reindex_all)
    {
	$reindex_all = 1 if (!$self->_info_read_cache());
    }
    # check for a partial reindex
    my $reindex_cat = $self->param('reindex_cat');
    # make sure there's no extraneous slashes
    $reindex_cat =~ s{^/}{};
    $reindex_cat =~ s{/$}{};
    if (!$reindex_all
	and $reindex_cat
	and exists $self->{categories}->{$reindex_cat}
	and defined $self->{categories}->{$reindex_cat})
    {
	$self->debug(1, "Info: reindexing $reindex_cat");
	while (my $file_id = each %{$self->{files}})
	{
	    if (($self->{files}->{$file_id}->{cat_id} eq $reindex_cat)
		or ($self->{files}->{$file_id}->{cat_id}
		    =~ /^$reindex_cat/)
	       )
	    {
		delete $self->{info}->{$file_id};
		$self->info($file_id);
	    }
	}
	$self->_info_save_cache();
    }
    elsif (!$reindex_all)
    {
	# If any files are in $self->{files} but not in $self->{info}
	# add them to the index
	my $newfiles = 0;
	while (my $file_id = each %{$self->{files}})
	{ exists $self->{info}->{$file_id}
	    or do {
		$newfiles++;
		delete $self->{info}->{$file_id};
		$self->info($file_id);
	    };
	}
	$self->debug(1, "Info: added $newfiles new files") if $newfiles;
	$self->_info_save_cache() if $newfiles;
    }

    if ($reindex_all) {
	$self->debug(1, "Info: reindexing ALL");
	while (my $file_id = each %{$self->{files}})
	{
	    delete $self->{info}->{$file_id};
	    $self->info($file_id);
	}
	$self->_info_save_cache();
    }
    else
    {
	# If any files not available, delete them and just save the cache
	if ($self->param('delindex'))
	{
	    $self->debug(1, "Info: checking for deleted files");
	    my $deletions = 0;
	    while (my $key = each %{$self->{info}})
	    { exists $self->{files}->{$key}
		or do { $deletions++; delete $self->{info}->{$key} };
	    }
	    $self->debug(1, "Info: deleted $deletions gone files")
		if $deletions;
	    $self->_info_save_cache() if $deletions;
	}
    }
} # index_info

=head1 Helper Methods

Methods which can be called from within other methods.

=head2 set_vars

    my %vars = $self->set_vars($flow_state);

    my %vars = $self->set_vars($flow_state, $current_entry, $entry_state);

    $content = $self->interpolate($chunk, $template, \%vars);

Sets variable hashes to be used in interpolation of templates.

This can be called from a flow action or from an entry action, and will
use the given state hashes accordingly.

This sets the variable hash as per the parent set_vars method,
with the addition of setting the .info fields (if any) as:

$self->info($entry_id, field=>$name) -> $info_<name>

=cut
sub set_vars {
    my $self = shift;
    my $flow_state = shift;
    my $current_entry = (@_ ? shift : undef);
    my $entry_state = (@_ ? shift : undef);

    my %vars = $self->SUPER::set_vars($flow_state, $current_entry, $entry_state);
    if (defined $current_entry)
    {
	my %info_vars = $self->info($current_entry->{id});
	if (%info_vars)
	{
	    while (my ($key, $val) = each %info_vars)
	    {
		my $nm = "info_$key";
		$vars{$nm} = $val;
	    }
	}
    }
    return %vars;
} # set_vars

=head2 info

    my %vars = $self->info($entry_id);

Gets the .info fields related to the given entry.

    my $val = $self->info($entry_id, field=>$name);

Get the value of the given .info field for this entry.

=cut
sub info {
    my $self = shift;
    my $entry_id = shift;
    my %args = (
	field=>undef,
	@_
    );
    my %info = ();
    # get the full info hash
    if (exists $self->{info}->{$entry_id}
	and defined $self->{info}->{$entry_id})
    {
	my $info_ref = $self->{info}->{$entry_id};
	%info = %{$info_ref};
    }
    elsif (!exists $self->{info}->{$entry_id})
    {
	my $look_file = File::Spec->catfile($self->{data_dir}, "$entry_id.info");
	%info = $self->read_info_file($look_file);
	$self->{info}->{$entry_id} = (%info ? \%info : undef);
    }
    if ($args{field})
    {
	if (exists $info{$args{field}}
	    and defined $info{$args{field}})
	{
	    $self->debug(3, "info{$args{field}}: $info{$args{field}}");
	    return $info{$args{field}};
	}
    }
    else
    {
	return %info;
    }
    return undef;
} # info

=head2 read_info_file

    my %info = $self->read_info_file($filename);

Parse a .info file.

Expects the fields to be in a Field:Value format,
with overflow to the next line(s).

=cut
sub read_info_file {
    my $self = shift;
    my $filename = shift;

    $self->debug(2, "read_info_file: $filename");
    my %info;
    if (-r $filename)
    {
	my $fh;
	open($fh, $filename)
		or die "couldn't open info file $filename: $!";
	$self->debug(2, "read_info_file: file found");

	my $prev_key = '';
	while (<$fh>) { 
		chomp;
		if (/^(\w+):\s*(.+)$/)
		{
		    my $key = $1;
		    my $val = $2;
		    $info{$key} = $val;
		    $prev_key = $key;
		    $self->debug(3, "info: $key=$val");
		}
		elsif (/^(\w+):\s*$/)
		{
		    # empty value
		    my $key = $1;
		    $info{$key} = '';
		    $prev_key = $key;
		    $self->debug(3, "info: $key=''");
		}
		elsif ($prev_key)
		{
		    $info{$prev_key} .= "\n";
		    $info{$prev_key} .= $_;
		    $self->debug(3, "info: $prev_key=$info{$prev_key}");
		}
	}
	close($fh);
	return %info;
    }
    return ();
} # read_info_file

=head1 Private Methods

Methods which may or may not be here in future.

=head2 _info_init_caching

Initialize the caching stuff used by index_entries

=cut
sub _info_init_caching {
    my $self = shift;

    return 0 if (!$self->{config}->{use_caching});
    eval "require Storable";
    if ($@) {
	$self->debug(1, "Info: cache disabled, Storable not available"); 
	$self->{config}->{use_caching} = 0; 
	return 0;
    }
    if (!Storable->can('lock_retrieve')) {
	$self->debug(1, "Info: cache disabled, Storable::lock_retrieve not available");
	$self->{config}->{use_caching} = 0;
	return 0;
    }
    $self->debug(1, "Info: using caching");
    return 1;
} # _info_init_caching

=head2 _info_read_cache

Reads the cached information used by index_entries

=cut
sub _info_read_cache {
    my $self = shift;

    return 0 if (!$self->{config}->{use_caching});
    $self->{info} = (-r $self->{config}->{info_cachefile}
	? Storable::lock_retrieve($self->{config}->{info_cachefile}) : undef);
    if ($self->{info}) {
	$self->debug(1, "Info: Using cached state");
	return 1;
    }
    $self->{info} = {};
    $self->debug(1, "Info: Flushing caches");
    return 0;
} # _info_read_cache

=head2 _info_save_cache

Saved the information gathered by index_entries to caches.

=cut
sub _info_save_cache {
    my $self = shift;
    return if (!$self->{config}->{use_caching});
    $self->debug(1, "Info: Saving caches");
    Storable::lock_store($self->{info}, $self->{config}->{info_cachefile});
} # _info_save_cache

=head1 INSTALLATION

Installation needs will vary depending on the particular setup a person
has.

=head2 Administrator, Automatic

If you are the administrator of the system, then the dead simple method of
installing the modules is to use the CPAN or CPANPLUS system.

    cpanp -i Posy::Plugin::Info

This will install this plugin in the usual places where modules get
installed when one is using CPAN(PLUS).

=head2 Administrator, By Hand

If you are the administrator of the system, but don't wish to use the
CPAN(PLUS) method, then this is for you.  Take the *.tar.gz file
and untar it in a suitable directory.

To install this module, run the following commands:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

Or, if you're on a platform (like DOS or Windows) that doesn't like the
"./" notation, you can do this:

   perl Build.PL
   perl Build
   perl Build test
   perl Build install

=head2 User With Shell Access

If you are a user on a system, and don't have root/administrator access,
you need to install Posy somewhere other than the default place (since you
don't have access to it).  However, if you have shell access to the system,
then you can install it in your home directory.

Say your home directory is "/home/fred", and you want to install the
modules into a subdirectory called "perl".

Download the *.tar.gz file and untar it in a suitable directory.

    perl Build.PL --install_base /home/fred/perl
    ./Build
    ./Build test
    ./Build install

This will install the files underneath /home/fred/perl.

You will then need to make sure that you alter the PERL5LIB variable to
find the modules.

Therefore you will need to change the PERL5LIB variable to add
/home/fred/perl/lib

	PERL5LIB=/home/fred/perl/lib:${PERL5LIB}

=head1 REQUIRES

    Posy
    Posy::Core
    Posy::Plugin::YamlConfig

    Test::More

=head1 SEE ALSO

perl(1).
Posy

=head1 BUGS

Please report any bugs or feature requests to the author.

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    perlkat AT katspace dot com
    http://www.katspace.com

=head1 COPYRIGHT AND LICENCE

Copyright (c) 2005 by Kathryn Andersen

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Posy::Plugin::Info
__END__
