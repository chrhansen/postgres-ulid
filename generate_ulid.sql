CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ULID according to the spec: https://github.com/ulid/spec
  -- generate_ulid() => 1GND65M56YS10B35V121ZS4D4
-- With prefix output in base58 (still sortable in Base 58)
  -- generate_ulid('base58', 'user') => user_BtnhF9Zpi2zMFsUfMXTCR
-- More usage: https://github.com/chrhansen/postgres-ulid#usage

CREATE OR REPLACE FUNCTION generate_ulid(output_base text default 'base32', -- also base58 or uuid
                                         prefix text default NULL,
                                         delimiter text default '_') RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    timestamp          BYTEA := E'\\000\\000\\000\\000\\000\\000';
    unix_time          BIGINT;
    ulid               BYTEA;
    base32_alphabet    TEXT := '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; -- Crockford's
    base58_alphabet    TEXT := '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'; -- Bitcoin
    ulid_base32_length INT := 26;
    return_string      TEXT := '';
BEGIN
    -- 6 timestamp bytes
    unix_time := (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT;
    FOR i IN 0..5 LOOP
        timestamp := SET_BYTE(timestamp, i, (unix_time >> (40 - i * 8))::BIT(8)::INTEGER);
    END LOOP;

    -- 10 entropy bytes
    ulid := timestamp || gen_random_bytes(10);

    -- Remove the leading '\x' and just keep the last 32 hex-characters
    return_string := SUBSTRING(ulid::text, 3, 32);

    CASE lower(output_base)
    WHEN 'base32' THEN
        return_string := hex_to_base(return_string, base32_alphabet);
        IF ulid_base32_length - length(return_string) > 0 THEN
           -- There will maximum be one (1) missing leading zero (0)
           return_string := repeat('0', ulid_base32_length - length(return_string)) || return_string;
        END IF;
    WHEN 'base58' THEN
        return_string := hex_to_base(return_string, base58_alphabet);
    WHEN 'uuid' THEN
       -- Do nothing, already a "hex-string". Can be cast to uuid: generate_ulid('uuid')::uuid
    ELSE
        RAISE EXCEPTION 'Unsupported base_name %', base_name
        USING HINT = 'Should be base32, base58, or uuid.';
    END CASE;

    IF prefix IS NOT NULL THEN
        return_string := prefix || delimiter || return_string;
    END IF;

    RETURN return_string;
END;
$$;

CREATE OR REPLACE FUNCTION hex_to_base(hexstr TEXT, base_alphabet TEXT) RETURNS TEXT AS $$
DECLARE
    bytes          BYTEA := ('\x' || hexstr)::BYTEA;
    leading_zeroes INT := 0;
    -- There are max. 40 (base10) digits in a 32 digit hex-number
    num            DECIMAL(40,0) := 0;
    base           DECIMAL(40,0) := 1;
    byte_value     INT;
    byte_val       INT;
    byte_values    INT[] DEFAULT ARRAY[]::INT[];
    modulo         INT;
    encoded_str    TEXT := '';
BEGIN
    -- This was built to convert 128-bit (32 hex-chars) UUIDs to another base,
    -- so we'll only promise that. Postgres DECIMAL can be up to ~131000 digits
    -- so bump the scale of 'num' and 'base' to convert bigger hex-numbers.
    IF length(hexstr) != 32 THEN
        RAISE EXCEPTION 'Hex-string >%< should be 32 characters long, but is % char(s).', hexstr, length(hexstr);
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
        base := base * 256; -- Two (2) hex-digits: 16 * 16 = 256
    END LOOP;

    -- Convert the up to 40-digit 'num', to the digits in 'base_alphabet'
    WHILE num > 0 LOOP
        modulo := num % length(base_alphabet);
        num := div(num, length(base_alphabet));
        byte_values := array_append(byte_values, modulo);
    END LOOP;

    -- Convert the 'byte_values' using characters from 'base_alphabet'. By
    -- prepending to 'encoded_str' the order of 'byte_values' is reversed.
    FOREACH byte_val IN ARRAY byte_values
    LOOP
        encoded_str := SUBSTRING(base_alphabet, byte_val + 1, 1) || encoded_str;
    END LOOP;

    -- Prepend first 'base_alphabet'-character to account for leading zeroes in 'hexstr'
    encoded_str := repeat(SUBSTRING(base_alphabet, 1, 1), leading_zeroes) || encoded_str;

    RETURN encoded_str;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
