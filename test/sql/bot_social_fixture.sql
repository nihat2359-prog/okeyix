\set ON_ERROR_STOP on
-- Run only in an empty, disposable local cluster on the dedicated test port.
DO $$ BEGIN
 IF inet_server_addr()<>'127.0.0.1'::inet OR inet_server_port()<>56489 THEN
   RAISE EXCEPTION 'LOCAL_BOT_SOCIAL_TEST_REQUIRED';
 END IF;
END $$;
DO $$ BEGIN
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF;
END $$;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT '00000000-0000-0000-0000-000000000001'::uuid $$;
CREATE TABLE users(id uuid PRIMARY KEY,is_bot boolean,username text);
CREATE TABLE tables(id uuid PRIMARY KEY,status text,max_players int,chat_enabled bool,last_winner_user_id uuid,last_finish_at timestamptz);
CREATE TABLE table_players(id uuid PRIMARY KEY,table_id uuid,user_id uuid,seat_index int);
CREATE TABLE table_messages(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),table_id uuid,sender_id uuid,role text,type text,content text,created_at timestamptz DEFAULT clock_timestamp());
CREATE TABLE profiles(id uuid PRIMARY KEY,coins int);
CREATE TABLE wallet_transactions(id uuid DEFAULT gen_random_uuid(),user_id uuid,amount int,reason text,type text,store text,note text);
CREATE TABLE okeyix_gift_catalog(id text,price int,enabled bool);
CREATE TABLE okeyix_table_gift_purchases(seq bigint GENERATED ALWAYS AS IDENTITY,request_id uuid,table_id uuid,sender_id uuid,recipient_id uuid,gift_id text,price int,wallet_transaction_id uuid);
CREATE TABLE okeyix_table_last_gifts(table_id uuid,user_id uuid,membership_id uuid,purchase_seq bigint,gift_id text,UNIQUE(table_id,user_id));
INSERT INTO users VALUES('00000000-0000-0000-0000-000000000001',false,'Oyuncu'),('00000000-0000-0000-0000-000000000002',true,'Mert');
INSERT INTO tables VALUES('00000000-0000-0000-0000-000000000010','playing',2,true,null,null);
INSERT INTO table_players SELECT id,'00000000-0000-0000-0000-000000000010',id,row_number() OVER () FROM users;
INSERT INTO profiles SELECT id,10000 FROM users;
INSERT INTO okeyix_gift_catalog VALUES('cay',1000,true);
