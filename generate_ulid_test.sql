-- Install pgTAP: https://pgxn.org/dist/pgtap/, then paste all this in psql or run
-- psql -d <db-with-pg-functions> -Xf generate_ulid_test.sql

CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

-- #################################################
-- 0. I don't know if/how to create vas/constants in pgTAP, so created this
-- function as a hack. Still I didn't know how to use it in the regex-checks.
-- #################################################

CREATE OR REPLACE FUNCTION alphabet(name TEXT) RETURNS TEXT AS $$
BEGIN
    IF name = 'base32' THEN
        RETURN '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    ELSIF name = 'base58' THEN
        RETURN '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    ELSE
        RAISE EXCEPTION 'Unsupported alphabet: %', name;
    END IF;
END; $$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- Plan count should be the number of tests
SELECT plan(11);

-- #################################################
-- 1. Function definition checks
-- #################################################
SELECT has_function(
    'generate_ulid',
    ARRAY ['text', 'text', 'text'],
    'generate_ulid exists'
);

SELECT has_function(
    'hex_to_base',
    ARRAY ['text', 'text'],
    'hex_to_base exists'
);

-- #################################################
-- 2. ULID Spec format
-- #################################################

SELECT matches(
    generate_ulid(),
    '^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$',
    'ULID is 26 characters and matches alphabet.'
);

-- #################################################
-- 3. ULID output using Base58
-- #################################################

SELECT matches(
    generate_ulid('base58'),
    '^[123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]{20,22}$',
    'Future ULIDs in Base58, should be 20 to 22 chars.'
);

-- #################################################
-- 4. ULID output in raw hex (UUID compatible)
-- #################################################

SELECT matches(
    generate_ulid('uuid'),
    '^[a-f0-9]{32}$',
    'ULID in hex should match UUIDv4 format.'
);

-- #################################################
-- 5. ULID with prefix
-- #################################################

SELECT matches(
    generate_ulid('base58', 'user'),
    '^user_+["123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"]{20,22}$',
    'Base58 ULID with `user_`-prefix.'
);

SELECT matches(
    generate_ulid('base32', 'acc', '-'),
    '^acc-+[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{26}$',
    'Base32-ULID with `acc-`-prefix.'
);

-- #################################################
-- 6. Is hex correctly converted
-- #################################################

-- Hex to base32
SELECT is(
    hex_to_base('01854a260cce8ac27aa31a6650208d85', alphabet('base32')),
    '1GN52C36EHB17N8RTCS8213C5',
    'Convert to Crockfords Base 32'
);

SELECT is(
    hex_to_base('018565340fefa54cf2f0fcabcbe752cc',  alphabet('base32')),
    '1GNJK83ZFMN6F5W7WNF5YEMPC',
    'Convert to Crockfords Base 32'
);

-- Hex to base58
SELECT is(
    hex_to_base('01854a260cce8ac27aa31a6650208d85',  alphabet('base58')),
    'BtgixbgGeX2fYfQdx2FMn',
    'Convert to Base 58'
);

SELECT is(
    hex_to_base('018565340fefa54cf2f0fcabcbe752cc',  alphabet('base58')),
    'BtrfqkYLnGhNSxktCFxA7',
    'Convert to Base 58'
);

ROLLBACK;
