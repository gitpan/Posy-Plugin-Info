package Posy::Plugin::Info;
use strict;

=head1 NAME

Posy::Plugin::Info - Posy plugin which give supplementary entry information.

=head1 VERSION

This describes version B<0.0101> of Posy::Plugin::Info.

=cut

our $VERSION = '0.0101';

=head1 SYNOPSIS

    @plugins = qw(Posy::Core
	...
	Posy::Plugin::Info
	...);

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
The info_sort requires Posy::Plugin::YamlConfig in order to set
the sort criteria.

This plugin replaces the 'sort_entries' action, the 'set_vars' action,
and provides an 'info' method for returning the info, if any, related to
an entry.

=head2 Configuration

This expects configuration settings in the $self->{config} hash,
which, in the default Posy setup, can be defined in the main "config"
file in the data directory.

=over

=item B<info_sort>

If true, enable sorting on .info information.  (default: false)

=item B<info_sort_spec>

Define the info-fields and order by which the entries will be sorted.

    info_sort_spec:
      order:
        - Author
        - Title
        - Order
      options:
        Title:
          reverse_order: 1
          type: title
        Order:
          type: number

The 'order' part of the spec is the order the fields are to be sorted by.
The 'options' part of the spec gives optional options for each field.  If
the 'reverse_order' is true, will sort that field in reverse order.  The
'type' option indicates what type of comparison should be done on that
field.  The types are as follows:

=over

=item string

A normal string comparison.  The default.

=item number

Compare as a number.

=item title

The field is a title; compare as if any leading "The" or "A" was not there.

=back

If after sorting by the fields, there is still no difference, this will
fall back to sorting by time, name or path, depending on what the
value of the config variable 'sort_type' is.

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
	and $self->{config}->{info_sort_spec})
    {
	# no point sorting if there's only one
	if (@{$flow_state->{entries}} > 1)
	{
	    my @sort_order =
		@{$self->{config}->{info_sort_spec}->{order}};
	    my %sort_numeric = ();
	    my %sort_reversed = ();

	    my $id_sort_type = (defined $self->{config}->{sort_type}
			     ? $self->{config}->{sort_type} : 'time_reversed');
	    my $id_sort_time = ($id_sort_type eq 'time');
	    my $id_sort_time_reversed = ($id_sort_type eq 'time_reversed');
	    my $id_sort_name = ($id_sort_type eq 'name');
	    my $id_sort_name_reversed = ($id_sort_type eq 'name_reversed');
	    my $id_sort_path = ($id_sort_type eq 'path');
	    my $id_sort_path_reversed = ($id_sort_type eq 'path_reversed');
	    
	    # pre-cache the actual comparison values
	    my %values = ();
	    foreach my $id (@{$flow_state->{entries}})
	    {
		my %a_info = $self->info($id);
		$values{$id} = {};
		foreach my $fn (@sort_order)
		{
		    my $a_sort_type =
			(
			 (exists
			  $self->{config}->{info_sort_spec}->{options}->{$fn}->{type}
			  and defined
			  $self->{config}->{info_sort_spec}->{options}->{$fn}->{type})
			 ? 
			 $self->{config}->{info_sort_spec}->{options}->{$fn}->{type}
			 : 'string'
			);
		    $sort_numeric{$fn} = ($a_sort_type eq 'number');
		    $sort_reversed{$fn} =
			$self->{config}->{info_sort_spec}->{options}->
			    {$fn}->{reverse_order};
		    if (!defined $a_info{$fn})
		    {
			if ($a_sort_type eq 'number')
			{
			    # sort undefined as zero
			    $values{$id}->{$fn} = 0;
			}
			else # string or title
			{
			    # sort undefined as the empty string
			    $values{$id}->{$fn} = '';
			}
		    }
		    else
		    {
			my $a_val = $a_info{$fn};
			if ($a_sort_type eq 'number')
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
			elsif ($a_sort_type eq 'title')
			{
			    # remove leading The or A from titles
			    $a_val =~ s/^(The\s+|A\s+)//;
			}
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
