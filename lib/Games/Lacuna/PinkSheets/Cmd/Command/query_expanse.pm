package Games::Lacuna::PinkSheets::Cmd::Command::query_expanse;
use 5.12.0;
use Moose;
our $VERSION = '0.01';
use namespace::autoclean;

use MooseX::Types::Path::Class qw(File);
use Games::Lacuna::PinkSheets::KiokuDB;
use Games::Lacuna::PinkSheets::ExpanseClient;

use DateTime;
use Try::Tiny;

extends qw(MooseX::App::Cmd::Command);

with qw(
  Games::Lacuna::PinkSheets::Cmd::Common
);

sub usage_desc { "query_expanse %o " }

has dsn => (
    isa           => "Str",
    is            => "ro",
    required      => 1,
    documentation => 'KiokuDB DSN',
);

has [qw(user pass)] => (
	isa => 'Str',
	is => 'ro',
);

has le_config => (
    isa           => 'Str',
    is            => 'ro',
    required      => 1,
    documentation => 'Lacuna Expanse Client Config',
);

has _namespace => (
    isa     => 'Str',
    reader  => 'namespace',
    default => 'Games::Lacuna::PinkSheets::Model::XML',
);

has _dir => (
    isa        => 'Games::Lacuna::PinkSheets::KiokuDB',
    reader     => 'dir',
    lazy_build => 1,
    handles    => [ 'new_scope', 'store', 'lookup', 'txn_do' ]
);

sub _build__dir {
    my $self = shift;
    Games::Lacuna::PinkSheets::KiokuDB->new(
        dsn        => $self->dsn,
        extra_args => { 
		user => $self->user,
		password => $self->pass,	
		create => 1 
	}
    );
}

has _le_client => (
    isa        => 'Games::Lacuna::PinkSheets::ExpanseClient',
    lazy_build => 1,
    handles    => [ 'session_id', 'trade_ministries', 'transporters' ],
);

sub _build__le_client {
    my $self = shift;
    Games::Lacuna::PinkSheets::ExpanseClient->new(
        config => $self->le_config,
        debug  => $self->verbose,
    );
}

use aliased 'Games::Lacuna::PinkSheets::Model::Trade';

sub save_trades {
    my ( $self, $trades, $type ) = @_;
    for my $trade (@$trades) {
        my $obj = $self->lookup( $trade->{id} )
          || Trade->new( %$trade, building => $type );
        $obj->last_seen( DateTime->now );
        $self->txn_do( sub { $self->store($obj); } );
    }
}

sub execute {
    my ( $self, $opt, $args ) = @_;
    my $scope = $self->new_scope;
    for my $type (qw(trade_ministries transporters)) {
        for ( $self->$type ) {
            my ( $id, $building ) = @$_;
            warn "working on building $id" if $self->verbose;
            my $data = $building->view_available_trades();
            $self->save_trades( $data->{trades}, $type );

            my $count = $data->{trade_count} - scalar @{ $data->{trades} };
            while ( $count > 0 ) {
                state $page = 2;
                warn "Checking page $page" if $self->verbose;
                my $data = $building->view_available_trades( $page++ );
                last unless scalar @{ $data->{trades} };
                $self->save_trades( $data->{trades}, $type );
                $count -= scalar @{ $data->{trades} };
                warn $count if $self->verbose;
            }
        }
    }
}

1;
__END__
