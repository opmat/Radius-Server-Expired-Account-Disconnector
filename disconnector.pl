#!/usr/bin/perl
use strict;
use warnings;
use DBI;
use Data::Dumper; # For debugging, remove in production

# Read database credentials from environment variables
my $host = $ENV{RADDB_HOST} or die "DB_HOST environment variable not set";
my $user = $ENV{RADDB_USER} or die "DB_USER environment variable not set";
my $pass = $ENV{RADDB_PASS} or die "DB_PASS environment variable not set";
my $database = $ENV{RADDB_NAME} or die "DB_NAME environment variable not set";

# Construct the DBI connection string
my $dsn = "dbi:mysql:host=$host;database=$database";

# Database connection handle
my $dbh;

# Connect to the database
eval {
    $dbh = DBI->connect($dsn, $user, $pass, {
        RaiseError => 1, # Raise exceptions on errors
        PrintError => 0, # Don't print errors to STDERR (we'll handle them)
        AutoCommit => 1,  # Set AutoCommit to 1
    });
};
if ($@) {
    die "Failed to connect to database: $@";
}

print "Successfully connected to the database.\n";

# The SQL query to retrieve user information
my $sql = q{
    SELECT
        ra.username,
        ra.nasipaddress,
        ra.framedipaddress,
        n.secret
    FROM radacct ra
    LEFT JOIN nas n ON ra.nasipaddress = n.nasname
    WHERE ra.username IN (SELECT username FROM rm_users WHERE expiration < NOW())
    AND ra.acctstoptime IS NULL 
};

# Prepare the SQL statement
my $sth = $dbh->prepare($sql);

# Execute the query
eval {
    $sth->execute();
};
if ($@) {
    die "Failed to execute query: $@";
}

print "Query executed.\n";

# Fetch and process each row
while (my $row = $sth->fetchrow_hashref()) {
    # Print the fetched row (for debugging)
    # print Dumper($row); #  Remove this line in production

    my $username      = $row->{username};
    my $nasipaddress  = $row->{nasipaddress};
    my $framedipaddress = $row->{framedipaddress};
    my $secret        = $row->{secret};

    # Check if required data exists.  Important for data integrity.
    if (not defined $username || not defined $nasipaddress || not defined $framedipaddress || not defined $secret) {
        warn "Skipping row due to missing data: username=$username, nasipaddress=$nasipaddress, framedipaddress=$framedipaddress\n";
        next; # Skip to the next iteration of the loop
    }
    
    # Construct and execute the radclient command
	my $command = qq(echo "User-Name=$username,Framed-IP-Address=$framedipaddress" | /usr/local/bin/radclient $nasipaddress:1700 disconnect $secret);

    # Print the command (for debugging)
    print "Executing command: $command\n"; 
    
    # Execute the radclient command using system with LIST form.
    my $result = system($command);
    
    if ($result == 0) {
        print "Successfully disconnected user $username from $nasipaddress.\n";
    } else {
        warn "Failed to disconnect user $username from $nasipaddress.  Command exited with status: $result\n";
    }
}

# Finish the statement handle
$sth->finish();

# Disconnect from the database
$dbh->disconnect();

print "Disconnected from the database.\n";

exit 0; # Exit cleanly
