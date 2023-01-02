# postgres-ulid
Universally Unique Lexicographically Sortable Identifier implementation for Postgres that also allow base58 output format as well as prefixed IDs.

E.g.

##### Default
```sql

SELECT generate_ulid();
     generate_ulid
-----------------------
 01GNT4FG7JEVZ89X7SCPDE9MP0
(1 row)
```

##### Base58 + prefix
``` sql
SELECT generate_ulid('base58', 'user');
     generate_ulid
-----------------------
 user_BtnmF6RFs4Y2u2xeyE8V9
(1 row)
```

Official specification page: https://github.com/ulid/spec



<h1 align="center">
	<br>
	<br>
	<img width="360" src="logo.png" alt="ulid">
	<br>
	<br>
	<br>
</h1>

# Universally Unique Lexicographically Sortable Identifier

UUID can be suboptimal for many use-cases because:

- It isn't the most character efficient way of encoding 128 bits of randomness
- UUID v1/v2 is impractical in many environments, as it requires access to a unique, stable MAC address
- UUID v3/v5 requires a unique seed and produces randomly distributed IDs, which can cause fragmentation in many data structures
- UUID v4 provides no other information than randomness which can cause fragmentation in many data structures

Instead, herein is proposed ULID:

- 128-bit compatibility with UUID
- 1.21e+24 unique ULIDs per millisecond
- Lexicographically sortable!
- Canonically encoded as a 26 character string, as opposed to the 36 character UUID
- Uses Crockford's base32 for better efficiency and readability (5 bits per character)
- Case insensitive
- No special characters (URL safe)
- Monotonic sort order (correctly detects and handles the same millisecond)

## Usage
#### ULID according to the spec

```sql
SELECT generate_ulid();
       generate_ulid
---------------------------
 01GNT4FG7JEVZ89X7SCPDE9MP0
(1 row)
```

#### Raw UUID version of the ULID

```sql
SELECT generate_ulid('uuid');
          generate_ulid
----------------------------------
 01855a915c5ca32ffd62ff9df9a70b3c
(1 row)
```
or cast to uuid to store in postgres UUID-type column
```sql
SELECT generate_ulid('uuid')::uuid;
                 uuid
--------------------------------------
 01855a91-5c5c-a32f-fd62-ff9df9a70b3c
(1 row)
```

#### Base58 version of the ULID

```sql
SELECT generate_ulid('base58');
     generate_ulid
-----------------------
 BtnmF6RFs4Y2u2xeyE8V9
(1 row)
```

#### Prefixed IDs
Defaults to `_`-delimiter.

```sql
SELECT generate_ulid('base58', 'user');
     generate_ulid
-----------------------
 user_BtnmF6RFs4Y2u2xeyE8V9
(1 row)
```

Prefixing a default ULID requires explicitly setting output base to 'base32'.
```sql
SELECT generate_ulid('base32', 'account', '-');
           generate_ulid
-----------------------------------
 account-01GNT4FG7JEVZ89X7SCPDE9MP0
(1 row)
```


## Specification

Below is the current specification of ULID as implemented in [ulid/javascript](https://github.com/ulid/javascript).

*Note: the binary format has not been implemented in JavaScript as of yet.*

```
 01AN4Z07BY      79KA1307SR9X4MV3

|----------|    |----------------|
 Timestamp          Randomness
   48bits             80bits
```

### Components

**Timestamp**
- 48 bit integer
- UNIX-time in milliseconds
- Won't run out of space 'til the year 10889 AD.

**Randomness**
- 80 bits
- Cryptographically secure source of randomness, if possible

### Sorting

The left-most character must be sorted first, and the right-most character sorted last (lexical order). The default ASCII character set must be used. Within the same millisecond, sort order is not guaranteed

### Canonical String Representation

```
ttttttttttrrrrrrrrrrrrrrrr

where
t is Timestamp (10 characters)
r is Randomness (16 characters)
```

#### Encoding

Crockford's Base32 is used as shown. This alphabet excludes the letters I, L, O, and U to avoid confusion and abuse.

```
0123456789ABCDEFGHJKMNPQRSTVWXYZ
```

#### Overflow Errors when Parsing Base32 Strings

Technically, a 26-character Base32 encoded string can contain 130 bits of information, whereas a ULID must only contain 128 bits. Therefore, the largest valid ULID encoded in Base32 is `7ZZZZZZZZZZZZZZZZZZZZZZZZZ`, which corresponds to an epoch time of `281474976710655` or `2 ^ 48 - 1`.

Any attempt to decode or encode a ULID larger than this should be rejected by all implementations, to prevent overflow bugs.

### Binary Layout and Byte Order

The components are encoded as 16 octets. Each component is encoded with the Most Significant Byte first (network byte order).

```
0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      32_bit_uint_time_high                    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|     16_bit_uint_time_low      |       16_bit_uint_random      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       32_bit_uint_random                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       32_bit_uint_random                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

Thanks to
- https://github.com/geckoboard/pgulid
- https://github.com/rubycocos/blockchain
