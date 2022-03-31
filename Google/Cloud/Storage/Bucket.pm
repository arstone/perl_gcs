package Google::Cloud::Storage::Bucket;

use strict;
use warnings;

use JSON qw(decode_json);
use JSON::WebToken;
use LWP::UserAgent ();
use File::Basename qw(basename);

sub new {

    my ( $class, $self ) = @_;

    # Check for required parameters
    my @required_params = qw(private_key_file client_email bucket_name);
    foreach my $param (@required_params) {
        unless ( exists $self->{$param} ) {
            die "Required parameter $param missing $!";
        }
    }

    bless $self, $class;

    $self->_initialize();

    return $self;

}

sub _initialize {

    my $self = shift;

    $self->{'private_key'}  = $self->_get_private_key();
    $self->{'access_token'} = $self->_authenticate();
}

sub _get_private_key {

    my $self = shift;

    open my $fh, '<', $self->{'private_key_file'} || die "Can't open google api private key file " . $self->{'private_key_file'} . " $!";
    binmode $fh;

    my $private_key = join( '', <$fh> );
    close $fh;

    return $private_key;

}

sub _authenticate {

    my $self = shift;

    my $url = 'https://oauth2.googleapis.com/token';
    my $exp = time() + 60 * 60;                        # Max ttl for token is 1 hour per Google

    $self->{'jwt'} = JSON::WebToken->encode(
        {   iss   => $self->{'client_email'},
            exp   => $exp,
            aud   => 'https://oauth2.googleapis.com/token',
            scope => 'https://www.googleapis.com/auth/cloud-platform',
            iat   => time()
        },
        $self->{'private_key'},
        'RS256'
    );

    my $grant_string = 'urn:ietf:params:oauth:grant-type:jwt-bearer';

    my $ua = LWP::UserAgent->new( timeout => 10 );

    my $response = $ua->post( $url, { grant_type => "$grant_string", assertion => $self->{'jwt'} } );

    my $access_token;
    if ( $response->is_success() ) {
        $access_token = decode_json( $response->decoded_content() );
    }
    else {
        die "Failed to authenticate to Google Cloud Storage: " . $response->status_line();
    }
    $access_token->{expire_time} = $access_token->{expires_in} + time();

    return $access_token;

}

sub _refresh_access_token {

    my $self = shift;

    my $time_buffer = 60;

    if ( $self->{'access_token'}->{'expire_time'} - $time_buffer < time() ) {
        $self->{'access_token'} = $self->_authenticate();
    }

    return;

}

sub list_files {

    my $self      = shift;
    my $directory = shift;

    $self->_refresh_access_token();

    my $access_token = $self->{'access_token'}->{'access_token'};
    my $url          = 'https://storage.googleapis.com/storage/v1/b/' . $self->{'bucket_name'} . '/o';
    if ($directory) {
        $url .= "?prefix=$directory";
    }

    my $ua = LWP::UserAgent->new( timeout => 10 );

    $ua->default_header( 'Authorization' => 'Bearer ' . $access_token );

    my $response = $ua->get($url);

    if ( $response->is_success() ) {

        # response from GCS is not decoding the / character
        my $response_string = $response->decoded_content();
        $response_string =~ s/%2F/\//g;
        return decode_json($response_string);
    }
    else {
        die "Failed in call to list_files: " . $response->status_line();
    }
}

sub upload_file {

    my ( $self, $source, $content_type, $destination ) = @_;

    my $filename = basename($source);

    if ($destination) {
        $destination =~ s/\/$//;
        $destination .= '/';
    }
    else {
        $destination = "";
    }

    unless ( -e $source ) {
        die "Unable to locate file: $filename";
    }

    # Set default content-type to binary if it was not passed in by caller
    $content_type = 'application/octet-stream' unless ($content_type);

    my $access_token = $self->{'access_token'}->{'access_token'};

    my $url = 'https://storage.googleapis.com/upload/storage/v1/b/' . $self->{'bucket_name'} . '/o';
    $url .= '?name=' . $destination . $filename . '&uploadType=media';

    my @params;
    push @params, 'Authorization'   => 'Bearer ' . $access_token;
    push @params, 'Content-Type'    => $content_type if ($content_type);
    
    my $ua      = LWP::UserAgent->new();
    my $request = HTTP::Request->new(
        POST => $url,
        \@params
    );
    my $buffer;
    open my $fh, '<', $source || die "Can't open $source for reading. $!";
    $request->content(
        sub {

            if ( sysread( $fh, $buffer, 1048576 ) ) {
                return $buffer;
            }
            else {
                close $fh;
                return '';
            }
        }
    );
    my $response = $ua->request($request);

    if ( $response->is_success() ) {
        return decode_json( $response->decoded_content() );
    }
    else {
        die 'Upload Failed: ' . $response->status_line();
    }
}

sub download_file {

    my ( $self, $filename, $save_dir ) = @_;

    unless ( -e $save_dir ) {
        die "Save directory does not exist: $save_dir";
    }

    $self->_refresh_access_token();

    my $access_token = $self->{'access_token'}->{'access_token'};

    my $url = 'https://storage.googleapis.com/storage/v1/b/' . $self->{'bucket_name'};
    $url .= '/o/' . $filename . '?alt=media';

    my $ua = LWP::UserAgent->new();
    my $r  = HTTP::Request->new(
        'GET' => $url,
        [ 'Authorization' => 'Bearer ' . $access_token ],
    );
    my $response = $ua->request( $r, "$save_dir/$filename" );

    if ( $response->is_success() ) {
        return 1;
    }
    else {
        die 'Download Failed: ' . $response->status_line();
    }
}

sub remove_file {

    my ( $self, $filename ) = @_;

    unless ($filename) {
        die "missing parameter to remove_file";
    }

    $self->_refresh_access_token();

    my $access_token = $self->{'access_token'}->{'access_token'};
    my $url          = 'https://storage.googleapis.com/storage/v1/b/';
    $url .= $self->{'bucket_name'} . '/o/' . $filename;

    my $ua = LWP::UserAgent->new( timeout => 10 );

    $ua->default_header( 'Authorization' => 'Bearer ' . $access_token );

    my $response = $ua->delete($url);

    if ( $response->is_success() ) {
        return 1;
    }
    else {
        die 'remove_file Failed: ' . $response->status_line();
    }
}

1;

__END__

=head1 NAME

Google::Cloud::Storage::Bucket

=head1 SYNOPSIS

    # Instantiate access to an existing bucket on the Google Cloud Storage platform

    my $bucket = Google::Cloud::Storage::Bucket->new( { 
        'private_key_file' => '/etc/private/gcs.key',
        'client_email' => 'email@test.com',
        'bucket_name' => 'my_bucket'}
    );

    # Get a JSON object containing the list of files 
    
    my $files = $bucket->list_files;

=head1 DESCRIPTION

L<GOOGLE::CLOUD::STORAGE::BUCKET> allows you to perform file operations on objects 
stored in Google Cloud Storage buckets.  It supports authentication with
the application service account model which is documented here:
L<Using OAuth 2.0 for Server to Server Applications|https://developers.google.com/identity/protocols/oauth2/service-account>

Under the hood, this module is using the Google Cloud Storage JSON API
L<Cloud Storage JSON API|https://cloud.google.com/storage/docs/json_api>


=head1 CONSTRUCTOR

=head2 new

    my $bucket = Google::Cloud::Storage::Bucket->new( 
        { 'private_key_file' => '/etc/private/gcs.key',
          'client_email' => 'email@test.com',
          'bucket_name' => 'my_bucket'}
    );

This method creates a new bucket object and authenticates to the Google Cloud Storage platform.  The
object will store and manage an access token.  The token has a 60 minute TTL.  The object will handle
refreshing the token automatically.

=head2 Required Parameters

=over

=item C<private_key_file>

The private key to the Google Service Account.

=item C<client_email>

The client email for the Google Service Account.

=item C<bucket_name>

The name of the Google Service Bucket

=back

=head1 METHODS

=over

=item C<list_files>

    my $files = $bucket->list_files;

Returns a hash containing the list of files in the bucket

=item C<upload_file>

    my $ret = $bucket->upload_file('/path/filename');

Uploads a file to the bucket.  

The method currently does not do file chunking or checksum validation

=item C<download_file>

    my $ret = $bucket->download_file('filename', '/destination/path');

Downloads a file from the bucket to local storage.

=item C<remove_file>

    my $ret = $bucket->remove_file('starman.log');

Removes a file from the Google bucket.  Be careful with this.  Once a file is deleted it cannot be restored.

=back

=head1 AUTHOR

Aaron Stone <aaron@mydestination.us>

=cut
