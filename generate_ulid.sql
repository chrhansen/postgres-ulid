CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ULID according to the spec: https://github.com/ulid/spec
  -- generate_ulid() => 1GND65M56YS10B35V121ZS4D4

-- Raw UUID version of the ULID
  -- generate_ulid('uuid')  => 01855a6687edcd779fb62f98173dfe5c
-- Or cast to uuid to store in postgres UUID-type column
  -- generate_ulid('uuid')::uuid   => 01855a66-87ed-cd77-9fb6-2f98173dfe5c

-- Base58-encoded ULID, optionally with a prefix to the ID
  -- generate_ulid('base58') => BtnhF9Zpi2zMFsUfMXTCR
  -- generate_ulid('base58', 'user') => user_BtnhF9Zpi2zMFsUfMXTCR

-- Prefixing a default ULID requires explicitly setting output_base to 'base32'
  -- generate_ulid('base32', 'account', '-') =>  account-1GND65M56YS10B35V121ZS4D4

CREATE OR REPLACE FUNCTION generate_ulid(output_base text default 'base32', -- also base58 or uuid
                                         prefix text default NULL,
                                         delimiter text default '_') RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    timestamp  BYTEA := E'\\000\\000\\000\\000\\000\\000';
    unix_time  BIGINT;
    ulid       BYTEA;

    return_string TEXT := '';
BEGIN
    -- 6 timestamp bytes
    unix_time := (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT;
    timestamp := SET_BYTE(timestamp, 0, (unix_time >> 40)::BIT(8)::INTEGER);
    timestamp := SET_BYTE(timestamp, 1, (unix_time >> 32)::BIT(8)::INTEGER);
    timestamp := SET_BYTE(timestamp, 2, (unix_time >> 24)::BIT(8)::INTEGER);
    timestamp := SET_BYTE(timestamp, 3, (unix_time >> 16)::BIT(8)::INTEGER);
    timestamp := SET_BYTE(timestamp, 4, (unix_time >> 8)::BIT(8)::INTEGER);
    timestamp := SET_BYTE(timestamp, 5, unix_time::BIT(8)::INTEGER);
    -- 10 entropy bytes
    ulid := timestamp || gen_random_bytes(10);

    -- Remove the leading '\x' and just keep the last 32 hex-characters
    return_string := SUBSTRING(ulid::text, 3, 32);

    output_base := lower(output_base);

    IF output_base = 'uuid' THEN
        -- Do nothing. The caller may cast 'return_string' to uuid-type, E.g.
        -- generate_ulid('uuid')::uuid => 01855a25-d825-7d7e-84b0-b95ec48aed85 (uuid-type)
    ELSE
        return_string := hex_to_base(return_string, output_base);
    END IF;

    IF prefix IS NOT NULL THEN
        return_string := prefix || delimiter || return_string;
    END IF;

    RETURN return_string;
END;
$$;

CREATE OR REPLACE FUNCTION hex_to_base(hexstr TEXT, base_name TEXT) RETURNS TEXT AS $$
DECLARE
    bytes BYTEA := ('\x' || hexstr)::BYTEA;
    leading_zeroes INT := 0;
    hexstr_length INT := length(hexstr);
    -- There are max. 40 (base10) digits in a 32 digit  hex
    num DECIMAL(40,0) := 0;
    base DECIMAL(40,0) := 1;

    byte_value INT;
    byte_val INT;
    byte_values INT[] DEFAULT ARRAY[]::INT[];
    modulo INT;

    crockfordbase32 TEXT := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    base58 TEXT := '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    base_alphabet TEXT;

    -- The final encoded string
    base_enc_string TEXT := '';
BEGIN
    -- This was built to convert 128-bit (32 chars hex) UUIDs to another base,
    -- so we'll not promise anything else. DECIMAL can take up to ~131000 digits
    -- so we can probably just bump the precision of 'num' and 'base', but that's
    -- for another time.
    IF length(hexstr) != 32 THEN
        RAISE EXCEPTION 'Hex-string >%< should be 32 characters long, but is % char(s).', hexstr, length(hexstr) ;
    END IF;

    -- Convert the 32-digit 'hexstr', to the base10 ('normal' digits) 'num'
    FOR hex_index IN REVERSE ((length(hexstr) / 2) - 1)..0 LOOP
        byte_value := get_byte(bytes, hex_index);
        IF byte_value = 0 THEN
            leading_zeroes := leading_zeroes + 1;
        ELSE
            leading_zeroes := 0;
            num := num + (base * byte_value);
        END IF;
        base := base * 256;
    END LOOP;

    CASE lower(base_name)
    WHEN 'base32' THEN
        base_alphabet := crockfordbase32;
    WHEN 'base58' THEN
        base_alphabet := base58;
    ELSE
        RAISE EXCEPTION 'Unsupported base_name %', base_name
        USING HINT = 'Should be base32 or base58.';
    END CASE;

    -- Convert the up-to 40-digit 'num', to the digirs base_name (base32, base58)
    WHILE num > 0 LOOP
        modulo := num % length(base_alphabet);
        num := div(num, length(base_alphabet));
        byte_values := array_append(byte_values, modulo);
    END LOOP;

    -- Convert the byte_values to corresponding characters/digits in the
    -- base_alphabet and build up the final string. Prepending each character to
    -- 'base_enc_string' also reverses the order from 'byte_values'.
    FOREACH byte_val IN ARRAY byte_values
    LOOP
        base_enc_string := SUBSTRING(base_alphabet, byte_val + 1, 1) || base_enc_string;
    END LOOP;

    -- Prepend first base_alphabet character to account for leading zeroes in 'hexstr'
    base_enc_string := repeat(SUBSTRING(base_alphabet, 1, 1), leading_zeroes) || base_enc_string;

    RETURN base_enc_string;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
