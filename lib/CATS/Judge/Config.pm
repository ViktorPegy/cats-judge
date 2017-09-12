package CATS::Judge::Config;

use strict;
use warnings;

use XML::Parser::Expat;
use CATS::Config;

sub dir_fields() { qw(cachedir logdir modulesdir solutionsdir resultsdir rundir workdir) }
sub required_fields() {
    dir_fields, qw(
    api
    name
    cats_url
    sleep_time
    stderr_file
    stdout_file
    formal_input_fname
    polygon_url
    report_file
) }
sub optional_fields() { qw(
    columns
    confess
    log_dump_size
    no_certificate_check
    save_child_stderr
    save_child_stdout
    show_child_stderr
    show_child_stdout
    proxy
) }
sub special_fields() { qw(checkers def_DEs defines DEs) }
sub security_fields() { qw(cats_password) }
sub de_fields() { qw(
    check compile encoding extension generate interactor_name run run_interactive runfile validate) }
sub param_fields() { required_fields, optional_fields, special_fields }

sub import {
    for (required_fields, optional_fields, special_fields, security_fields) {
        no strict 'refs';
        my $x = $_;
        *{"$_[0]::$_"} = sub { $_[0]->{$x} };
    }
}

sub new {
    my ($class) = shift;
    my $self = { defines => {}, DEs => {}, checkers => {}, def_DEs => {} };
    bless $self, $class;
    $self;
}

sub apply_defines {
    my ($self, $value) = @_;
    $value //= '';
    my $defines = $self->{defines};
    $value =~ s/$_/$defines->{$_}/g
        for sort { length $b <=> length $a || $a cmp $b } keys %$defines;
    $value;
}

sub _read_attributes {
    my ($self, $dest, $atts, @fields) = @_;
    for (@fields) {
        $dest->{$_} = $self->apply_defines($atts->{$_}) if exists $atts->{$_};
    }
}

sub read_file {
    my ($self, $file, $overrides) = @_;

    my $parser = XML::Parser::Expat->new;
    $parser->setHandlers(Start => sub {
        my ($p, $el, %atts) = @_;
        my $h = {
            judge => sub {
                $self->_read_attributes($self, \%atts, required_fields, optional_fields);
            },
            security => sub {
                $self->_read_attributes($self, \%atts, security_fields);
            },
            de => sub {
                my $code = $atts{code} or die 'de: code required';
                my $dd = $self->def_DEs;
                for (split / /, $atts{extension} // '') {
                    die "duplicate default extension $_ for DEs $dd->{$_} and $code" if $dd->{$_};
                    $dd->{$_} = $code;
                }
                $self->_read_attributes($self->DEs->{$code} //= {}, \%atts, de_fields);
            },
            define => sub {
                $atts{name} or die 'define: name required';
                defined $atts{value} or die "define $atts{name}: value required";
                $self->{defines}->{$atts{name}} = $self->apply_defines($atts{value});
            },
            checker => sub {
                $atts{name} or die 'checker: name required';
                $atts{exec} or die "checker $atts{name}: exec required";
                $self->checkers->{$atts{name}} = $self->apply_defines($atts{exec});
            },
        }->{$el} or die "Unknown tag $el";
        $h->();
    });
    $parser->parse($file);

    if ($overrides) {
        $self->{$_} = $overrides->{$_} for keys %$overrides;
    }
    defined $self->{$_} or die "config: undefined $_" for required_fields;
    $_ = File::Spec->rel2abs($_, cats_dir) for @{$self}{dir_fields()};
}

sub print_helper {
    my ($val, $keys, $depth, $bare) = @_;
    for my $k (sort @$keys) {
        print "$depth$k =" unless $bare;
        my $v = $val->{$k};
        if (ref $v) {
            print "\n";
            print_helper($v, [ keys %$v ], "$depth    ");
        }
        else {
            print $bare ? "$v\n" : " $v\n";
        }
    }
}

sub print_params {
    my ($self, $regexp, $bare) = @_;
    my $r = qr/$regexp/;
    print_helper($self, [ grep /$r/, keys %$self ], '', $bare);
}

1;
