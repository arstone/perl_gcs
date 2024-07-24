# Google::Cloud::Storage::Bucket

## Overview

`Google::Cloud::Storage::Bucket` is a Perl module that allows you to perform file operations on objects stored in Google Cloud Storage buckets. It supports authentication using the application service account model, which is documented here: [Using OAuth 2.0 for Server to Server Applications](https://developers.google.com/identity/protocols/oauth2/service-account).

This module uses the [Google Cloud Storage JSON API](https://cloud.google.com/storage/docs/json_api) under the hood.

## Installation

To install this module, you can use CPAN:

```bash
cpan Google::Cloud::Storage::Bucket
```

## Usage

### Instantiate Access to an Existing Bucket

```perl
use Google::Cloud::Storage::Bucket;

my $bucket = Google::Cloud::Storage::Bucket->new({
    'private_key_file' => '/etc/private/gcs.key',
    'client_email'     => 'email@test.com',
    'bucket_name'      => 'my_bucket'
});
```

### List Files in the Bucket

```perl
my $files = $bucket->list_files;
```

## Constructor

### `new`

```perl
my $bucket = Google::Cloud::Storage::Bucket->new({
    'private_key_file' => '/etc/private/gcs.key',
    'client_email'     => 'email@test.com',
    'bucket_name'      => 'my_bucket'
});
```

This method creates a new bucket object and authenticates to the Google Cloud Storage platform. The object will store and manage an access token, which has a 60-minute TTL. The object will handle refreshing the token automatically.

### Required Parameters

- **`private_key_file`**: The private key to the Google Service Account.
- **`client_email`**: The client email for the Google Service Account.
- **`bucket_name`**: The name of the Google Service Bucket.

## Methods

### `list_files`

```perl
my $files = $bucket->list_files;
```

Returns a hash containing the list of files in the bucket.

### `upload_file`

```perl
my $ret = $bucket->upload_file('/path/filename');
```

Uploads a file to the bucket. This method currently does not do file chunking or checksum validation.

### `download_file`

```perl
my $ret = $bucket->download_file('filename', '/destination/path');
```

Downloads a file from the bucket to local storage.

### `remove_file`

```perl
my $ret = $bucket->remove_file('starman.log');
```

Removes a file from the Google bucket. Be careful with this. Once a file is deleted, it cannot be restored.

## Author

Aaron Stone <aaron@mydestination.us>

---

For more detailed information, refer to the official [Google Cloud Storage documentation](https://cloud.google.com/storage/docs/json_api).
