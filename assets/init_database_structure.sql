--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

--
-- Name: oldtulp; Type: SCHEMA; Schema: -; Owner: tulp
--

CREATE SCHEMA oldtulp;


ALTER SCHEMA oldtulp OWNER TO tulp;

--
-- Name: plpgsql; Type: PROCEDURAL LANGUAGE; Schema: -; Owner: postgres
--

CREATE OR REPLACE PROCEDURAL LANGUAGE plpgsql;


ALTER PROCEDURAL LANGUAGE plpgsql OWNER TO postgres;

SET search_path = public, pg_catalog;

--
-- Name: crc32(text); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION crc32(word text) RETURNS bigint
    LANGUAGE plpgsql IMMUTABLE
    AS $$
          DECLARE tmp bigint;
          DECLARE i int;
          DECLARE j int;
          DECLARE byte_length int;
          DECLARE word_array bytea;
          BEGIN
            IF COALESCE(word, '') = '' THEN
              return 0;
            END IF;

            i = 0;
            tmp = 4294967295;
            byte_length = bit_length(word) / 8;
            word_array = decode(replace(word, E'\\', E'\\\\'), 'escape');
            LOOP
              tmp = (tmp # get_byte(word_array, i))::bigint;
              i = i + 1;
              j = 0;
              LOOP
                tmp = ((tmp >> 1) # (3988292384 * (tmp & 1)))::bigint;
                j = j + 1;
                IF j >= 8 THEN
                  EXIT;
                END IF;
              END LOOP;
              IF i >= byte_length THEN
                EXIT;
              END IF;
            END LOOP;
            return (tmp # 4294967295);
          END
        $$;


ALTER FUNCTION public.crc32(word text) OWNER TO tulp;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: category_assignments; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE category_assignments (
    id integer NOT NULL,
    category_id integer,
    business_id integer
);


ALTER TABLE public.category_assignments OWNER TO tulp;

--
-- Name: delete_from_business_ratings(category_assignments); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION delete_from_business_ratings(r category_assignments) RETURNS void
    LANGUAGE plpgsql
    AS $$
  begin
    delete
      from business_ratings br
      where br.business_id = r.business_id
        and br.rating_id not in (
          -- выбираем рейтинги, которые остались у заведения
          select cr.rating_id
            from categories_ratings cr
            join category_assignments ca on ca.category_id = cr.category_id
            where ca.business_id = r.business_id
        );
  end;
$$;


ALTER FUNCTION public.delete_from_business_ratings(r category_assignments) OWNER TO tulp;

--
-- Name: insert_into_business_ratings(category_assignments); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION insert_into_business_ratings(r category_assignments) RETURNS void
    LANGUAGE plpgsql
    AS $$
  begin
    insert into business_ratings (business_id, rating_id, title)
      -- выбираем все рейтинги для данной категории за исключением уже существующих
      select r.business_id, cr.rating_id, rat.title
      from categories_ratings cr
      join ratings rat on rat.id = cr.rating_id
      where cr.category_id = r.category_id
        and cr.rating_id not in (select rating_id from business_ratings where business_id = r.business_id);
  end;
$$;


ALTER FUNCTION public.insert_into_business_ratings(r category_assignments) OWNER TO tulp;

--
-- Name: load_business_owners(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_business_owners() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  a_deleted_at DATE;
  an_approved BOOLEAN;
  rec RECORD;
  error VARCHAR(255);
BEGIN
  FOR rec IN 
    SELECT u.id, u.login, u.hashed_password, u.salt, u.email, u.created_at, u.updated_at,
           u.deleted, u.approved, t.firstname, t.lastname
    FROM oldtulp.users u LEFT JOIN oldtulp.tulpers t ON u.id = t.user_id
    WHERE u.status = 'N' AND u.role = 1 LOOP
  BEGIN
      IF rec.deleted = 0 THEN a_deleted_at := NULL; ELSE a_deleted_at := current_date; END IF;
      IF rec.approved = 0 THEN an_approved := FALSE; ELSE an_approved := TRUE; END IF;
      INSERT INTO business_owners (id, email, encrypted_password, password_salt, login, created_at, updated_at, 
         deleted_at, approved, first_name, last_name) 
      VALUES
        (rec.id, COALESCE(rec.email, '(none)'), rec.hashed_password, rec.salt, rec.login, rec.created_at, rec.updated_at, 
        a_deleted_at, an_approved, rec.firstname, rec.lastname);
      UPDATE oldtulp.users SET status = 'Y' WHERE id = rec.id;
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.users SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_business_owners() OWNER TO tulp;

--
-- Name: load_businesses(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_businesses() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  a_deleted BOOLEAN;
  error VARCHAR(255);
BEGIN
  FOR rec IN SELECT * FROM oldtulp.businesses WHERE status = 'N' LOOP
  BEGIN
    IF rec.deleted = 0 THEN a_deleted := FALSE; ELSE a_deleted := TRUE; END IF;
    INSERT INTO businesses (id, business_owner_id, name, info, address, created_at, updated_at, deleted, creator_id, city_id, general_category_id,
        oldtulp_contact, rating) VALUES
    (rec.id, rec.user_id, rec.name, rec.info, rec.address, rec.created_at, rec.updated_at, a_deleted, rec.creator_id, rec.city_id, rec.category1_id,
       rec.contact, COALESCE(rec.rate_avg,0));
    UPDATE oldtulp.businesses SET status = 'Y' WHERE id = rec.id;  
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.businesses SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_businesses() OWNER TO tulp;

--
-- Name: load_categories(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_categories() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  error VARCHAR(255);
BEGIN
  FOR rec IN SELECT * FROM oldtulp.categories WHERE status = 'N' LOOP
  BEGIN
    INSERT INTO categories (id, name, translit, parent_id, prepositional_singular, prepositional_plural, created_at, updated_at)
     VALUES (rec.id, rec.name, rec.nickname, rec.supcat_id, rec.pp_name, rec.pp1_name, rec.created_at, rec.updated_at);
    UPDATE oldtulp.categories SET status = 'Y' WHERE id = rec.id;  
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.categories SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_categories() OWNER TO tulp;

--
-- Name: load_categories_for_business(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_categories_for_business() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  error VARCHAR(255);
BEGIN
  FOR rec IN SELECT * FROM oldtulp.businesses WHERE status = 'Y' AND status_category = 'N' LOOP
  BEGIN
    IF rec.category1_id IS NOT NULL THEN
      INSERT INTO category_assignments (category_id, business_id) VALUES
      (rec.category1_id, rec.id);
    END IF;
    IF rec.category2_id IS NOT NULL THEN
      INSERT INTO category_assignments (category_id, business_id) VALUES
      (rec.category2_id, rec.id);
    END IF;
    IF rec.category3_id IS NOT NULL THEN
      INSERT INTO category_assignments (category_id, business_id) VALUES
      (rec.category3_id, rec.id);
    END IF;
    UPDATE oldtulp.businesses SET status_category = 'Y' WHERE id = rec.id;  
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.businesses SET status_category = 'E', diagnostics_category = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_categories_for_business() OWNER TO tulp;

--
-- Name: load_cities(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_cities() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  error VARCHAR(255);
BEGIN
  FOR rec IN SELECT * FROM oldtulp.cities WHERE status = 'N' LOOP
  BEGIN
    INSERT INTO cities (id, name, translit, parent_case, created_at, updated_at) VALUES
    (rec.id, rec.name, rec.nickname, rec.rp_name, rec.created_at, rec.updated_at);
    UPDATE oldtulp.cities SET status = 'Y' WHERE id = rec.id;  
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.cities SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_cities() OWNER TO tulp;

--
-- Name: load_cities2(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_cities2() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  next_id INTEGER;
  this_id INTEGER;
  error VARCHAR(255);
BEGIN
  SELECT MAX(id) + 1 INTO this_id FROM cities;
  IF next_id IS NULL THEN
    next_id := 1;
  END IF;

  FOR rec IN SELECT * FROM oldtulp.cities2 WHERE status = 'N' LOOP
  BEGIN
    SELECT MAX(id) INTO this_id FROM cities WHERE name = rec.name;
    IF this_id IS NULL THEN
      this_id = next_id;
      next_id := next_id + 1;
      INSERT INTO cities (id, name, translit, parent_case, created_at, updated_at) VALUES
        (this_id, rec.name, rec.translit, rec.padeg, current_date, current_date);
    ELSE
      UPDATE cities SET translit = rec.translit WHERE id = this_id;
    END IF;
    UPDATE oldtulp.cities2 SET status = 'Y', new_id = this_id WHERE name = rec.name;
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.cities2 SET status = 'E', diagnostics = error WHERE name = rec.name;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_cities2() OWNER TO tulp;

--
-- Name: load_comments(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_comments() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  a_deleted BOOLEAN;
  error VARCHAR(255);
BEGIN
  FOR rec IN SELECT * FROM oldtulp.comments WHERE status = 'N' AND root_type = 'Review' LOOP
  BEGIN
    IF rec.deleted = 0 THEN a_deleted := FALSE; ELSE a_deleted := TRUE; END IF;
    INSERT INTO comments (id, text, parent_id, commentable_id, commentable_type, created_at, updated_at, deleted, user_id) VALUES
    (rec.id, rec.text, rec.target_id, rec.root_id, rec.root_type, rec.created_at, rec.updated_at, a_deleted, rec.author_id);
    UPDATE oldtulp.comments SET status = 'Y' WHERE id = rec.id;  
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.comments SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_comments() OWNER TO tulp;

--
-- Name: load_compliment_types(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_compliment_types() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  error VARCHAR(255);
BEGIN
  FOR rec IN SELECT * FROM oldtulp.compliment_types WHERE status = 'N' LOOP
  BEGIN
    INSERT INTO compliment_types (id, text, created_at, updated_at) VALUES
    (rec.id, rec.name, rec.created_at, rec.updated_at);
    UPDATE oldtulp.compliment_types SET status = 'Y' WHERE id = rec.id;  
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.compliment_types SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_compliment_types() OWNER TO tulp;

--
-- Name: load_compliments(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_compliments() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  error VARCHAR(255);
BEGIN
  FOR rec IN SELECT * FROM oldtulp.compliments WHERE status = 'N' LOOP
  BEGIN
    INSERT INTO compliments (id, custom_text, created_at, updated_at, user_id, compliment_type_id) VALUES
    (rec.id, rec.text, rec.created_at, rec.updated_at, rec.target_user_id, rec.compliment_type_id);
    UPDATE oldtulp.compliments SET status = 'Y' WHERE id = rec.id;  
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.compliments SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_compliments() OWNER TO tulp;

--
-- Name: load_fan_favs(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_fan_favs() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  error VARCHAR(255);
BEGIN
  FOR rec IN SELECT * FROM oldtulp.fan_favs WHERE status = 'N' LOOP
  BEGIN
    INSERT INTO favouriteships (id, admirer_id, favourite_id, created_at, updated_at) VALUES
    (rec.id, rec.fan_id, rec.fav_id, rec.created_at, rec.updated_at);
    UPDATE oldtulp.fan_favs SET status = 'Y' WHERE id = rec.id;  
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.fan_favs SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_fan_favs() OWNER TO tulp;

--
-- Name: load_feedbacks(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_feedbacks() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  a_status VARCHAR(50);
  error VARCHAR(255);
BEGIN
  FOR rec IN SELECT * FROM oldtulp.feedbacks WHERE status = 'N' LOOP
  BEGIN
    a_status := NULL;
    IF rec.viewed = 1 THEN a_status = 'Просмотрено'; ELSE a_status = 'Новое'; END IF;
    INSERT INTO feedbacks (id, title, body, user_id, oldtulp_ip, email, oldtulp_page, created_at, updated_at, oldtulp_options, status, feedback_type) VALUES
    (rec.id, substr(rec.text, 1, 50), rec.text, rec.user_id, rec.ip, rec.email, rec.page, rec.created_at, rec.updated_at, rec.options, a_status, 
      'Предложение');
    UPDATE oldtulp.feedbacks SET status = 'Y' WHERE id = rec.id;  
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.feedbacks SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_feedbacks() OWNER TO tulp;

--
-- Name: load_moderator_users(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_moderator_users() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  a_deleted_at DATE;
  an_approved BOOLEAN;
  rec RECORD;
  error VARCHAR(255);
BEGIN
  FOR rec IN 
    SELECT u.id, u.login, u.hashed_password, u.salt, u.email, u.created_at, u.updated_at,
           u.city_id, u.deleted, u.approved, m.id m_id, m.name lastname, c.timezone
    FROM oldtulp.users u LEFT JOIN oldtulp.moderators m ON u.id = m.user_id
                         LEFT JOIN oldtulp.cities c ON u.city_id = c.id
    WHERE u.status = 'N' AND u.role = 2 LOOP
  BEGIN
    IF rec.m_id IS NOT NULL THEN
      IF rec.deleted = 0 THEN a_deleted_at := NULL; ELSE a_deleted_at := current_date; END IF;
      IF rec.approved = 0 THEN an_approved := FALSE; ELSE an_approved := TRUE; END IF;
      INSERT INTO users (id, email, encrypted_password, password_salt, login, created_at, updated_at, city_id, 
         deleted_at, approved, last_name, time_zone, roles_mask) 
      VALUES
        (rec.id, COALESCE(rec.email, '(none)'), rec.hashed_password, rec.salt, rec.login, rec.created_at, rec.updated_at, rec.city_id, 
        a_deleted_at, an_approved, rec.lastname, rec.timezone, 2);
      UPDATE oldtulp.users SET status = 'Y' WHERE id = rec.id;
    ELSE
      UPDATE oldtulp.users SET status = 'E', diagnostics = 'Нет записи в moderators' WHERE id = rec.id;
    END IF;
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.users SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_moderator_users() OWNER TO tulp;

--
-- Name: load_private_messages(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_private_messages() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  a_deleted_at DATE;
  a_read_at DATE;
  error VARCHAR(255);
BEGIN
  FOR rec IN SELECT * FROM oldtulp.private_messages WHERE status = 'N' AND canceled = 0 LOOP
  BEGIN
    IF rec.deleted = 1 THEN a_deleted_at := current_date; ELSE a_deleted_at := NULL; END IF;
    IF rec.viewed = 1 THEN a_read_at := current_date; ELSE a_read_at := NULL; END IF;
    INSERT INTO messages (id, sender_id, recipient_id, body, created_at, updated_at, read_at, deleted_at, subject) VALUES
    (rec.id, rec.author_id, rec.target_id, rec.text, rec.created_at, rec.updated_at, a_read_at, a_deleted_at, SUBSTR(rec.text, 1, 50));
    UPDATE oldtulp.private_messages SET status = 'Y' WHERE id = rec.id;  
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.private_messages SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_private_messages() OWNER TO tulp;

--
-- Name: load_regular_users(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_regular_users() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  a_birthday DATE;
  a_gender VARCHAR(1);
  a_deleted_at DATE;
  an_approved BOOLEAN;
  rec RECORD;
  error VARCHAR(255);
BEGIN
  FOR rec IN 
    SELECT u.id, u.login, u.hashed_password, u.salt, u.email, u.created_at, u.updated_at,
           u.city_id, u.deleted, u.approved,
           t.firstname, t.lastname, t.birthday, t.birthmonth, t.birthyear, t.info, t.created_at,
           t.updated_at, t.sex, t.id t_id, t.contact, t.interests, c.timezone
    FROM oldtulp.users u LEFT JOIN oldtulp.tulpers t ON u.id = t.user_id
                         LEFT JOIN oldtulp.cities c ON u.city_id = c.id
    WHERE u.status = 'N' AND u.role = 0 LOOP
  BEGIN
    IF rec.t_id IS NOT NULL THEN
      a_birthday := NULL;
      IF rec.birthday IS NOT NULL AND rec.birthmonth IS NOT NULL AND rec.birthyear IS NOT NULL THEN
        BEGIN
          SELECT DATE (rec.birthyear || '-' || rec.birthmonth || '-' || rec.birthday) INTO a_birthday; 
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
      END IF;
      a_gender := NULL;
      IF rec.sex = 0 THEN a_gender := 'f'; ELSE a_gender := 'm'; END IF;
      IF rec.deleted = 0 THEN a_deleted_at := NULL; ELSE a_deleted_at := current_date; END IF;
      IF rec.approved = 0 THEN an_approved := FALSE; ELSE an_approved := TRUE; END IF;
      INSERT INTO users (id, email, encrypted_password, password_salt, login, created_at, updated_at, city_id, 
         deleted_at, approved, first_name, last_name, birthday, description, gender, time_zone, oldtulp_contact, oldtulp_interests) 
      VALUES
        (rec.id, COALESCE(rec.email, '(none)'), rec.hashed_password, rec.salt, rec.login, rec.created_at, rec.updated_at, rec.city_id, 
        a_deleted_at, an_approved, rec.firstname, rec.lastname, a_birthday, rec.info, a_gender, rec.timezone, rec.contact, rec.interests);
      UPDATE oldtulp.users SET status = 'Y' WHERE id = rec.id;
    ELSE
      UPDATE oldtulp.users SET status = 'E', diagnostics = 'Нет записи в tulpers' WHERE id = rec.id;
    END IF;
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.users SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_regular_users() OWNER TO tulp;

--
-- Name: load_reviews(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION load_reviews() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  a_deleted_at DATE;
  an_approved BOOLEAN;
  error VARCHAR(255);
BEGIN
  FOR rec IN SELECT * FROM oldtulp.reviews WHERE status = 'N' LOOP
  BEGIN
    IF rec.deleted = 0 THEN a_deleted_at := NULL; ELSE a_deleted_at := current_date; END IF;
    IF rec.approved = 0 THEN an_approved := FALSE; ELSE an_approved := TRUE; END IF;
    INSERT INTO reviews (id, user_id, business_id, text, created_at, updated_at, deleted_at, title, approved, business_rating) VALUES
    (rec.id, rec.author_id, rec.business_id, rec.text, rec.created_at, rec.updated_at, a_deleted_at, rec.name, an_approved, rec.rate);
    UPDATE oldtulp.reviews SET status = 'Y' WHERE id = rec.id;  
--    COMMIT;
  EXCEPTION 
    WHEN OTHERS THEN
      error = sqlerrm; 
      UPDATE oldtulp.reviews SET status = 'E', diagnostics = error WHERE id = rec.id;  
--      COMMIT;
  END;
  END LOOP;
END;
$$;


ALTER FUNCTION public.load_reviews() OWNER TO tulp;

--
-- Name: recalculate_business_ratings(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION recalculate_business_ratings() RETURNS void
    LANGUAGE plpgsql
    AS $$
  begin
    update business_ratings br set total = ar.total, number = ar.number from average_rates ar where ar.business_id = br.business_id and ar.rating_id = br.rating_id;
    update businesses set rating = ar.rating from average_ratings ar where id = ar.business_id;
  end;
$$;


ALTER FUNCTION public.recalculate_business_ratings() OWNER TO tulp;

--
-- Name: recalculate_business_ratings_for_one_business(integer); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION recalculate_business_ratings_for_one_business(b_id integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
  declare
    rat "businesses"."rating"%TYPE;
  begin
    update business_ratings br set total = ar.total, number = ar.number from average_rates ar where ar.rating_id = br.rating_id and ar.business_id = br.business_id and br.business_id = b_id;
    select into rat ar.rating from average_ratings ar where b_id = ar.business_id;
    update businesses set rating = rat where id = b_id;
    return rat;
  end;
$$;


ALTER FUNCTION public.recalculate_business_ratings_for_one_business(b_id integer) OWNER TO tulp;

--
-- Name: recreate_review_visits(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION recreate_review_visits() RETURNS void
    LANGUAGE sql
    AS $$
  drop table if exists review_visits;
  create table "review_visits" as
    select review_id, count(*) as number from (
      select impressionable_id as review_id
      from impressions
      where impressionable_type = 'Review'
      group by review_id, ip_address, session_hash
    ) _ group by review_id;
  create unique index on "review_visits" (review_id);
$$;


ALTER FUNCTION public.recreate_review_visits() OWNER TO tulp;

--
-- Name: sequences_prepare(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION sequences_prepare() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  an_id INTEGER;
BEGIN
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM businesses;
  EXECUTE 'ALTER SEQUENCE businesses_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM business_owners;
  EXECUTE 'ALTER SEQUENCE business_owners_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM users;
  EXECUTE 'ALTER SEQUENCE users_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM category_assignments;
  EXECUTE 'ALTER SEQUENCE category_assignments_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM categories;
  EXECUTE 'ALTER SEQUENCE categories_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM cities;
  EXECUTE 'ALTER SEQUENCE cities_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM comments;
  EXECUTE 'ALTER SEQUENCE comments_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM compliments;
  EXECUTE 'ALTER SEQUENCE compliments_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM compliment_types;
  EXECUTE 'ALTER SEQUENCE compliment_types_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM feedbacks;
  EXECUTE 'ALTER SEQUENCE feedbacks_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM messages;
  EXECUTE 'ALTER SEQUENCE messages_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM reviews;
  EXECUTE 'ALTER SEQUENCE reviews_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM favouriteships;
  EXECUTE 'ALTER SEQUENCE favouriteships_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM assets;
  EXECUTE 'ALTER SEQUENCE assets_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM questions;
  EXECUTE 'ALTER SEQUENCE questions_id_seq RESTART WITH ' || an_id;
  SELECT COALESCE (MAX(id), 0) + 1 INTO an_id FROM answers;
  EXECUTE 'ALTER SEQUENCE answers_id_seq RESTART WITH ' || an_id;
END;
$$;


ALTER FUNCTION public.sequences_prepare() OWNER TO tulp;

--
-- Name: update_business_ratings(); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION update_business_ratings() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  begin
    if (tg_op = 'INSERT') then
      perform insert_into_business_ratings(new);
    elsif (tg_op = 'DELETE') then
      perform delete_from_business_ratings(old);
    end if;
    return null;
  exception when unique_violation then
    return null;
  end;
$$;


ALTER FUNCTION public.update_business_ratings() OWNER TO tulp;

--
-- Name: update_review_visits(integer); Type: FUNCTION; Schema: public; Owner: tulp
--

CREATE FUNCTION update_review_visits(integer) RETURNS void
    LANGUAGE plpgsql
    AS $_$
  declare
    counter record;

  begin
    for counter in select review_id, count(*) as number from (select impressionable_id as review_id from impressions where impressionable_type = 'Review' and id > $1 group by review_id, ip_address, session_hash) _ group by review_id loop
      update review_visits set number = number + counter.number where review_id = counter.review_id;
      if not found then
        insert into review_visits values (counter.review_id, counter.number);
      end if;
    end loop;
  end;
$_$;


ALTER FUNCTION public.update_review_visits(integer) OWNER TO tulp;

--
-- Name: array_accum(anyelement); Type: AGGREGATE; Schema: public; Owner: tulp
--

CREATE AGGREGATE array_accum(anyelement) (
    SFUNC = array_append,
    STYPE = anyarray,
    INITCOND = '{}'
);


ALTER AGGREGATE public.array_accum(anyelement) OWNER TO tulp;

SET search_path = oldtulp, pg_catalog;

--
-- Name: attribute_types; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE attribute_types (
    id integer NOT NULL,
    name character varying(255) DEFAULT NULL::character varying,
    nickname character varying(255) DEFAULT NULL::character varying,
    metatype integer,
    choices text,
    setter character varying(255) DEFAULT NULL::character varying,
    categories text,
    canceled integer DEFAULT 0 NOT NULL,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.attribute_types OWNER TO tulp;

--
-- Name: business_votes; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE business_votes (
    id integer NOT NULL,
    tulper_id integer,
    business_id integer,
    month character varying(255) DEFAULT NULL::character varying,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    canceled integer DEFAULT 0 NOT NULL,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.business_votes OWNER TO tulp;

--
-- Name: businesses; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE businesses (
    id integer NOT NULL,
    user_id integer,
    name character varying(255),
    contact text,
    info text,
    photo character varying(255),
    address character varying(255),
    rate_num integer,
    rate_sum integer DEFAULT 0 NOT NULL,
    rate_avg integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    deleted integer DEFAULT 0 NOT NULL,
    votes integer DEFAULT 0 NOT NULL,
    login character varying(255),
    creator_id integer,
    closed integer DEFAULT 0,
    city_id integer,
    category1_id integer,
    category2_id integer,
    category3_id integer,
    topcategory1_id integer,
    topcategory2_id integer,
    topcategory3_id integer,
    coordinates character varying(255),
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255),
    status_category character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics_category character varying(255)
);


ALTER TABLE oldtulp.businesses OWNER TO tulp;

--
-- Name: categories; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE categories (
    id integer NOT NULL,
    name character varying(255),
    nickname character varying(255),
    supcat_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    count integer DEFAULT 0,
    pp_name character varying(255),
    pp1_name character varying(255),
    paramz text,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.categories OWNER TO tulp;

--
-- Name: cities; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE cities (
    id integer NOT NULL,
    name character varying(255),
    nickname character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    timezone character varying(255),
    rp_name character varying(255),
    rank integer,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.cities OWNER TO tulp;

--
-- Name: cities2; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE cities2 (
    name character varying(255) NOT NULL,
    translit character varying(255),
    padeg character varying(255),
    new_id integer,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.cities2 OWNER TO tulp;

--
-- Name: comments; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE comments (
    id integer NOT NULL,
    text text,
    target_id integer,
    root_id integer,
    root_type character varying(255),
    level integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    author_id integer,
    deleted integer DEFAULT 0 NOT NULL,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.comments OWNER TO tulp;

--
-- Name: compliment_types; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE compliment_types (
    id integer NOT NULL,
    name character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.compliment_types OWNER TO tulp;

--
-- Name: compliments; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE compliments (
    id integer NOT NULL,
    text text,
    target_id integer,
    target_type character varying(255),
    author_id integer,
    compliment_type_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    target_user_id integer,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.compliments OWNER TO tulp;

--
-- Name: event_categories; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE event_categories (
    id integer NOT NULL,
    name character varying(255) DEFAULT NULL::character varying,
    nickname character varying(255) DEFAULT NULL::character varying,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.event_categories OWNER TO tulp;

--
-- Name: events; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE events (
    id integer NOT NULL,
    name character varying(255) DEFAULT NULL::character varying,
    event_category_id integer,
    min_price integer,
    max_price integer,
    where_id integer,
    where_text text,
    start timestamp without time zone,
    finish timestamp without time zone,
    author_id integer,
    description text,
    count integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    nickname character varying(255) DEFAULT NULL::character varying,
    photo character varying(255) DEFAULT NULL::character varying,
    deleted integer DEFAULT 0,
    city_id integer,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.events OWNER TO tulp;

--
-- Name: fan_favs; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE fan_favs (
    id integer NOT NULL,
    fan_id integer,
    fav_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    canceled integer DEFAULT 0 NOT NULL,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.fan_favs OWNER TO tulp;

--
-- Name: feedbacks; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE feedbacks (
    id integer NOT NULL,
    text text,
    user_id integer,
    ip character varying(255),
    email character varying(255),
    page character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    options text,
    viewed integer DEFAULT 0,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.feedbacks OWNER TO tulp;

--
-- Name: memberships; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE memberships (
    id integer NOT NULL,
    user_id integer,
    event_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    canceled integer DEFAULT 0 NOT NULL,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.memberships OWNER TO tulp;

--
-- Name: moderation_events; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE moderation_events (
    id integer NOT NULL,
    moderator_id integer,
    action character varying(255) DEFAULT NULL::character varying,
    target_id integer,
    target_type character varying(255) DEFAULT NULL::character varying,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    canceled integer DEFAULT 0 NOT NULL,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.moderation_events OWNER TO tulp;

--
-- Name: moderators; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE moderators (
    id integer NOT NULL,
    user_id integer,
    name character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    deleted integer DEFAULT 0,
    rank integer DEFAULT 1
);


ALTER TABLE oldtulp.moderators OWNER TO tulp;

--
-- Name: photos; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE photos (
    id integer NOT NULL,
    target_id integer,
    target_type character varying(255) DEFAULT NULL::character varying,
    author_id integer,
    description text,
    data_file_name character varying(255) DEFAULT NULL::character varying,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    deleted integer DEFAULT 0 NOT NULL,
    approved integer DEFAULT 1,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.photos OWNER TO tulp;

--
-- Name: private_messages; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE private_messages (
    id integer NOT NULL,
    author_id integer,
    target_id integer,
    text text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    viewed integer DEFAULT 0,
    deleted integer DEFAULT 0 NOT NULL,
    canceled integer DEFAULT 0 NOT NULL,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.private_messages OWNER TO tulp;

--
-- Name: review_questions; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE review_questions (
    id integer NOT NULL,
    review_id integer,
    business_id integer,
    attribute_type_id integer,
    value text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    canceled integer DEFAULT 0 NOT NULL,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.review_questions OWNER TO tulp;

--
-- Name: review_votes; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE review_votes (
    id integer NOT NULL,
    review_id integer,
    user_id integer,
    vote integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    canceled integer DEFAULT 0 NOT NULL,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.review_votes OWNER TO tulp;

--
-- Name: reviews; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE reviews (
    id integer NOT NULL,
    author_id integer,
    business_id integer,
    rate integer,
    text text,
    vote_num integer DEFAULT 0 NOT NULL,
    vote_sum integer DEFAULT 0 NOT NULL,
    vote_avg integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    deleted integer DEFAULT 0 NOT NULL,
    rating integer DEFAULT 0 NOT NULL,
    name character varying(255),
    approved integer DEFAULT 0,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.reviews OWNER TO tulp;

--
-- Name: tulpers; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE tulpers (
    id integer NOT NULL,
    user_id integer,
    firstname character varying(255),
    lastname character varying(255),
    birthday integer,
    birthmonth integer,
    birthyear integer,
    contact text,
    interests text,
    info text,
    security text,
    photo character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    deleted integer DEFAULT 0 NOT NULL,
    rating integer DEFAULT 0 NOT NULL,
    login character varying(255),
    sex integer,
    want_newsletter integer DEFAULT 1,
    status_avatar character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics_avatar character varying(255)
);


ALTER TABLE oldtulp.tulpers OWNER TO tulp;

--
-- Name: users; Type: TABLE; Schema: oldtulp; Owner: tulp; Tablespace: 
--

CREATE TABLE users (
    id integer NOT NULL,
    login character varying(255),
    hashed_password character varying(255),
    salt character varying(255),
    email character varying(255),
    role integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    city_id integer,
    deleted integer,
    approved integer,
    status character varying(1) DEFAULT 'N'::character varying NOT NULL,
    diagnostics character varying(255)
);


ALTER TABLE oldtulp.users OWNER TO tulp;

SET search_path = public, pg_catalog;

--
-- Name: answers; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE answers (
    id integer NOT NULL,
    question_id integer,
    choice_id integer,
    answerable_type character varying(255),
    answerable_id integer,
    text character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    user_id integer
);


ALTER TABLE public.answers OWNER TO tulp;

--
-- Name: answers_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE answers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.answers_id_seq OWNER TO tulp;

--
-- Name: answers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE answers_id_seq OWNED BY answers.id;


--
-- Name: assets; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE assets (
    id integer NOT NULL,
    data_file_name character varying(255),
    data_content_type character varying(255),
    data_file_size integer,
    created_at timestamp without time zone,
    data_updated_at timestamp without time zone,
    "primary" boolean DEFAULT false,
    note text,
    attachable_type character varying(255),
    attachable_id integer,
    approved boolean DEFAULT false NOT NULL,
    creator_id integer,
    type character varying(255) NOT NULL,
    review_id integer,
    delete_at timestamp without time zone
);


ALTER TABLE public.assets OWNER TO tulp;

--
-- Name: assets_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.assets_id_seq OWNER TO tulp;

--
-- Name: assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE assets_id_seq OWNED BY assets.id;


--
-- Name: attachings; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE attachings (
    id integer NOT NULL,
    attachable_id integer,
    asset_id integer,
    attachable_type character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.attachings OWNER TO tulp;

--
-- Name: attachings_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE attachings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.attachings_id_seq OWNER TO tulp;

--
-- Name: attachings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE attachings_id_seq OWNED BY attachings.id;


--
-- Name: authentications; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE authentications (
    id integer NOT NULL,
    user_id integer,
    provider character varying(255),
    uid character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    link character varying(255),
    friends_cache text,
    profile_cache text
);


ALTER TABLE public.authentications OWNER TO tulp;

--
-- Name: authentications_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE authentications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.authentications_id_seq OWNER TO tulp;

--
-- Name: authentications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE authentications_id_seq OWNED BY authentications.id;


--
-- Name: business_ratings; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE business_ratings (
    id integer NOT NULL,
    business_id integer,
    rating_id integer,
    total integer DEFAULT 0 NOT NULL,
    number integer DEFAULT 0 NOT NULL,
    title character varying(255)
);


ALTER TABLE public.business_ratings OWNER TO tulp;

--
-- Name: rates; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE rates (
    id integer NOT NULL,
    business_id integer,
    user_id integer,
    rating_id integer,
    review_id integer,
    rate integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    title character varying(255)
);


ALTER TABLE public.rates OWNER TO tulp;

--
-- Name: latest_rates; Type: VIEW; Schema: public; Owner: tulp
--

CREATE VIEW latest_rates AS
    SELECT DISTINCT ON (r.user_id, r.business_id, r.rating_id) r.id, r.business_id, r.user_id, r.rating_id, r.review_id, r.rate, r.created_at, r.updated_at, r.title FROM (rates r JOIN business_ratings br USING (business_id, rating_id)) ORDER BY r.user_id, r.business_id, r.rating_id, r.updated_at DESC;


ALTER TABLE public.latest_rates OWNER TO tulp;

--
-- Name: average_rates; Type: VIEW; Schema: public; Owner: tulp
--

CREATE VIEW average_rates AS
    SELECT latest_rates.business_id, latest_rates.rating_id, sum(latest_rates.rate) AS total, count(latest_rates.id) AS number FROM latest_rates GROUP BY latest_rates.business_id, latest_rates.rating_id;


ALTER TABLE public.average_rates OWNER TO tulp;

--
-- Name: average_ratings; Type: VIEW; Schema: public; Owner: tulp
--

CREATE VIEW average_ratings AS
    SELECT average_rates.business_id, CASE WHEN (sum(average_rates.number) = (0)::numeric) THEN (0)::numeric ELSE (sum(average_rates.total) / sum(average_rates.number)) END AS rating FROM average_rates GROUP BY average_rates.business_id;


ALTER TABLE public.average_ratings OWNER TO tulp;

--
-- Name: banners; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE banners (
    id integer NOT NULL,
    user_id integer NOT NULL,
    business_id integer,
    url character varying(255),
    clicked_count integer DEFAULT 0 NOT NULL,
    "position" character varying(255) NOT NULL,
    city_id integer NOT NULL,
    note character varying(255),
    image_file_name character varying(255),
    image_content_type character varying(255),
    image_file_size integer,
    image_updated_at timestamp without time zone,
    token character varying(40),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    page character varying(255),
    show_until date,
    viewed_at timestamp without time zone
);


ALTER TABLE public.banners OWNER TO tulp;

--
-- Name: banners_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE banners_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.banners_id_seq OWNER TO tulp;

--
-- Name: banners_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE banners_id_seq OWNED BY banners.id;


--
-- Name: battle_requests; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE battle_requests (
    id integer NOT NULL,
    battle_id integer,
    requester_uid integer,
    receiver_uid integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.battle_requests OWNER TO tulp;

--
-- Name: battle_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE battle_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.battle_requests_id_seq OWNER TO tulp;

--
-- Name: battle_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE battle_requests_id_seq OWNED BY battle_requests.id;


--
-- Name: battle_users; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE battle_users (
    id integer NOT NULL,
    uid integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    rank integer DEFAULT 0,
    posted_rank integer
);


ALTER TABLE public.battle_users OWNER TO tulp;

--
-- Name: battle_users_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE battle_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.battle_users_id_seq OWNER TO tulp;

--
-- Name: battle_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE battle_users_id_seq OWNED BY battle_users.id;


--
-- Name: battle_votes; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE battle_votes (
    id integer NOT NULL,
    user_uid integer,
    business_id integer,
    battle_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.battle_votes OWNER TO tulp;

--
-- Name: battle_votes_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE battle_votes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.battle_votes_id_seq OWNER TO tulp;

--
-- Name: battle_votes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE battle_votes_id_seq OWNED BY battle_votes.id;


--
-- Name: battles; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE battles (
    id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    end_at timestamp without time zone,
    callback_after_end_completed boolean DEFAULT false
);


ALTER TABLE public.battles OWNER TO tulp;

--
-- Name: battles_businesses; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE battles_businesses (
    battle_id integer,
    business_id integer
);


ALTER TABLE public.battles_businesses OWNER TO tulp;

--
-- Name: battles_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE battles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.battles_id_seq OWNER TO tulp;

--
-- Name: battles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE battles_id_seq OWNED BY battles.id;


--
-- Name: business_categories; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE business_categories (
    id integer NOT NULL,
    business_id integer,
    category_id integer,
    general boolean
);


ALTER TABLE public.business_categories OWNER TO tulp;

--
-- Name: business_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE business_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.business_categories_id_seq OWNER TO tulp;

--
-- Name: business_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE business_categories_id_seq OWNED BY business_categories.id;


--
-- Name: business_owners; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE business_owners (
    id integer NOT NULL,
    email character varying(255) DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying(128) DEFAULT ''::character varying NOT NULL,
    password_salt character varying(255) DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying(255),
    remember_token character varying(255),
    remember_created_at timestamp without time zone,
    sign_in_count integer DEFAULT 0,
    current_sign_in_at timestamp without time zone,
    last_sign_in_at timestamp without time zone,
    current_sign_in_ip character varying(255),
    last_sign_in_ip character varying(255),
    first_name character varying(255),
    last_name character varying(255),
    login character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    approved boolean DEFAULT false NOT NULL,
    deleted_at timestamp without time zone,
    assets_count integer DEFAULT 0,
    "position" character varying(255)
);


ALTER TABLE public.business_owners OWNER TO tulp;

--
-- Name: business_owners_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE business_owners_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.business_owners_id_seq OWNER TO tulp;

--
-- Name: business_owners_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE business_owners_id_seq OWNED BY business_owners.id;


--
-- Name: business_ratings_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE business_ratings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.business_ratings_id_seq OWNER TO tulp;

--
-- Name: business_ratings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE business_ratings_id_seq OWNED BY business_ratings.id;


--
-- Name: businesses; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE businesses (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    business_owner_id integer,
    creator_id integer,
    contact text,
    info text,
    address character varying(255),
    deleted boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    city_id integer,
    rating numeric(3,2) DEFAULT NULL::numeric,
    assets_count integer DEFAULT 0,
    translit character varying(255),
    general_category_id integer,
    lat double precision,
    long double precision,
    oldtulp_contact text,
    delta boolean DEFAULT true NOT NULL,
    approved boolean DEFAULT false NOT NULL,
    reviews_count integer DEFAULT 0,
    office_hours character varying(1000),
    base_service character varying(1000),
    device character varying(1000),
    history text,
    discounts character varying(1000),
    business_owner_info text,
    email character varying(255),
    highlight boolean DEFAULT false NOT NULL,
    address_street character varying(255),
    address_house character varying(255),
    address_part character varying(255),
    address_building character varying(255),
    address_room character varying(255),
    address_metro_stations character varying(255),
    address_other character varying(255),
    contacts_phone text,
    contacts_fax character varying(255),
    contacts_email character varying(255),
    contacts_site character varying(255),
    other_categories text,
    category_translit character varying(255),
    last_review_date timestamp without time zone,
    working_time character varying(255),
    from_yandex boolean DEFAULT false NOT NULL,
    info_approved boolean DEFAULT false NOT NULL
);


ALTER TABLE public.businesses OWNER TO tulp;

--
-- Name: businesses_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE businesses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.businesses_id_seq OWNER TO tulp;

--
-- Name: businesses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE businesses_id_seq OWNED BY businesses.id;


--
-- Name: categories; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE categories (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    prepositional_singular character varying(255),
    prepositional_plural character varying(255),
    translit character varying(255),
    parent_id integer,
    lft integer,
    rgt integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.categories OWNER TO tulp;

--
-- Name: category_questions; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE category_questions (
    category_id integer NOT NULL,
    question_id integer NOT NULL,
    number integer
);


ALTER TABLE public.category_questions OWNER TO tulp;

--
-- Name: questions; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE questions (
    id integer NOT NULL,
    title character varying(255),
    note character varying(255),
    question_type character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    main boolean DEFAULT true NOT NULL,
    "group" character varying(255),
    negative character varying(255)
);


ALTER TABLE public.questions OWNER TO tulp;

--
-- Name: businesses_questions; Type: VIEW; Schema: public; Owner: tulp
--

CREATE VIEW businesses_questions AS
    SELECT DISTINCT ON (b.id, q.id) b.id AS business_id, q.id AS question_id FROM ((((businesses b JOIN category_assignments ca ON ((ca.business_id = b.id))) JOIN categories c ON ((c.id = ca.category_id))) JOIN category_questions cq ON ((cq.category_id = c.id))) JOIN questions q ON ((q.id = cq.question_id)));


ALTER TABLE public.businesses_questions OWNER TO tulp;

--
-- Name: categories_ratings; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE categories_ratings (
    category_id integer NOT NULL,
    rating_id integer
);


ALTER TABLE public.categories_ratings OWNER TO tulp;

--
-- Name: ratings; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE ratings (
    id integer NOT NULL,
    title character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.ratings OWNER TO tulp;

--
-- Name: businesses_ratings; Type: VIEW; Schema: public; Owner: tulp
--

CREATE VIEW businesses_ratings AS
    SELECT DISTINCT ON (b.id, r.id, r.title) b.id AS business_id, r.id AS rating_id, r.title FROM ((((businesses b JOIN category_assignments ca ON ((ca.business_id = b.id))) JOIN categories c ON ((c.id = ca.category_id))) JOIN categories_ratings cr ON ((cr.category_id = c.id))) JOIN ratings r ON ((r.id = cr.rating_id)));


ALTER TABLE public.businesses_ratings OWNER TO tulp;

--
-- Name: businesses_users; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE businesses_users (
    business_id integer,
    user_id integer
);


ALTER TABLE public.businesses_users OWNER TO tulp;

--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.categories_id_seq OWNER TO tulp;

--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE categories_id_seq OWNED BY categories.id;


--
-- Name: category_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE category_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.category_assignments_id_seq OWNER TO tulp;

--
-- Name: category_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE category_assignments_id_seq OWNED BY category_assignments.id;


--
-- Name: category_ranks; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE category_ranks (
    id integer NOT NULL,
    category_id integer NOT NULL,
    city_id integer NOT NULL,
    rank double precision DEFAULT 0 NOT NULL,
    business_count integer DEFAULT 0 NOT NULL,
    root boolean NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.category_ranks OWNER TO tulp;

--
-- Name: category_ranks_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE category_ranks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.category_ranks_id_seq OWNER TO tulp;

--
-- Name: category_ranks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE category_ranks_id_seq OWNED BY category_ranks.id;


--
-- Name: choices; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE choices (
    id integer NOT NULL,
    title character varying(255),
    question_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.choices OWNER TO tulp;

--
-- Name: choices_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE choices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.choices_id_seq OWNER TO tulp;

--
-- Name: choices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE choices_id_seq OWNED BY choices.id;


--
-- Name: cities; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE cities (
    id integer NOT NULL,
    name character varying(255),
    translit character varying(255),
    parent_case character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    example_addresses text,
    example_businesses text,
    example_terms text,
    region_id integer,
    town boolean DEFAULT false NOT NULL,
    reviews_count integer,
    preposition_case character varying(255),
    blank boolean DEFAULT true NOT NULL
);


ALTER TABLE public.cities OWNER TO tulp;

--
-- Name: cities_coupons; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE cities_coupons (
    city_id integer NOT NULL,
    coupon_id integer NOT NULL
);


ALTER TABLE public.cities_coupons OWNER TO tulp;

--
-- Name: cities_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE cities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.cities_id_seq OWNER TO tulp;

--
-- Name: cities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE cities_id_seq OWNED BY cities.id;


--
-- Name: cities_users; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE cities_users (
    user_id integer NOT NULL,
    city_id integer NOT NULL
);


ALTER TABLE public.cities_users OWNER TO tulp;

--
-- Name: comments; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE comments (
    id integer NOT NULL,
    creator_id integer,
    text text NOT NULL,
    parent_id integer,
    lft integer,
    rgt integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    commentable_type character varying(255),
    commentable_id integer,
    deleted boolean DEFAULT false NOT NULL,
    deleted_at timestamp without time zone,
    deleted_by integer,
    creator_type character varying(255)
);


ALTER TABLE public.comments OWNER TO tulp;

--
-- Name: comments_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE comments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.comments_id_seq OWNER TO tulp;

--
-- Name: comments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE comments_id_seq OWNED BY comments.id;


--
-- Name: contacts; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE contacts (
    id integer NOT NULL,
    user_id integer,
    provider character varying(255),
    login character varying(255),
    privacy integer DEFAULT 0,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.contacts OWNER TO tulp;

--
-- Name: contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contacts_id_seq OWNER TO tulp;

--
-- Name: contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE contacts_id_seq OWNED BY contacts.id;


--
-- Name: countries; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE countries (
    id integer NOT NULL,
    name character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    reviews_count integer
);


ALTER TABLE public.countries OWNER TO tulp;

--
-- Name: countries_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE countries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.countries_id_seq OWNER TO tulp;

--
-- Name: countries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE countries_id_seq OWNED BY countries.id;


--
-- Name: double_users; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE double_users (
    id integer,
    email character varying(255)
);


ALTER TABLE public.double_users OWNER TO tulp;

--
-- Name: emails; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE emails (
    id integer NOT NULL,
    "from" character varying(255),
    "to" character varying(255),
    last_send_attempt integer DEFAULT 0,
    mail text,
    created_on timestamp without time zone
);


ALTER TABLE public.emails OWNER TO tulp;

--
-- Name: emails_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE emails_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.emails_id_seq OWNER TO tulp;

--
-- Name: emails_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE emails_id_seq OWNED BY emails.id;


--
-- Name: entries; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE entries (
    id integer NOT NULL,
    user_id integer,
    document_id integer,
    document_type character varying(255),
    cents integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.entries OWNER TO tulp;

--
-- Name: entries_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.entries_id_seq OWNER TO tulp;

--
-- Name: entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE entries_id_seq OWNED BY entries.id;


--
-- Name: exports; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE exports (
    id integer NOT NULL,
    business_id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.exports OWNER TO tulp;

--
-- Name: exports_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE exports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.exports_id_seq OWNER TO tulp;

--
-- Name: exports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE exports_id_seq OWNED BY exports.id;


--
-- Name: facts; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE facts (
    business_id integer,
    answer_id integer NOT NULL,
    question_id integer,
    title character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.facts OWNER TO tulp;

--
-- Name: favorites; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE favorites (
    id integer NOT NULL,
    user_id integer NOT NULL,
    favorable_id integer NOT NULL,
    favorable_type character varying(255) NOT NULL,
    kind character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.favorites OWNER TO tulp;

--
-- Name: favorites_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE favorites_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.favorites_id_seq OWNER TO tulp;

--
-- Name: favorites_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE favorites_id_seq OWNED BY favorites.id;


--
-- Name: favouriteships; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE favouriteships (
    id integer NOT NULL,
    favourite_id integer,
    admirer_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.favouriteships OWNER TO tulp;

--
-- Name: favouriteships_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE favouriteships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.favouriteships_id_seq OWNER TO tulp;

--
-- Name: favouriteships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE favouriteships_id_seq OWNED BY favouriteships.id;


--
-- Name: feedbacks; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE feedbacks (
    id integer NOT NULL,
    feedback_type character varying(255),
    body text,
    user_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    reportable_id integer,
    reportable_type character varying(255),
    email character varying(255),
    title character varying(255),
    deleted boolean DEFAULT false NOT NULL,
    status character varying(255) NOT NULL,
    details text,
    oldtulp_options text,
    oldtulp_ip character varying(255),
    oldtulp_page character varying(255)
);


ALTER TABLE public.feedbacks OWNER TO tulp;

--
-- Name: feedbacks_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE feedbacks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.feedbacks_id_seq OWNER TO tulp;

--
-- Name: feedbacks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE feedbacks_id_seq OWNED BY feedbacks.id;


--
-- Name: friendship_requests; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE friendship_requests (
    id integer NOT NULL,
    sender_id integer,
    recipient_id integer,
    state character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.friendship_requests OWNER TO tulp;

--
-- Name: friendship_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE friendship_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.friendship_requests_id_seq OWNER TO tulp;

--
-- Name: friendship_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE friendship_requests_id_seq OWNED BY friendship_requests.id;


--
-- Name: friendships; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE friendships (
    id integer NOT NULL,
    user_id integer,
    friend_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.friendships OWNER TO tulp;

--
-- Name: friendships_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE friendships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.friendships_id_seq OWNER TO tulp;

--
-- Name: friendships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE friendships_id_seq OWNED BY friendships.id;


--
-- Name: gas; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE gas (
    id integer NOT NULL,
    page_path character varying(255),
    pageviews integer DEFAULT 0,
    male integer DEFAULT 0,
    female integer DEFAULT 0,
    tulper integer DEFAULT 0,
    date date,
    type character varying(255),
    business_id integer,
    redirects integer DEFAULT 0
);


ALTER TABLE public.gas OWNER TO tulp;

--
-- Name: gas_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE gas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.gas_id_seq OWNER TO tulp;

--
-- Name: gas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE gas_id_seq OWNED BY gas.id;


--
-- Name: impressions; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE impressions (
    id integer NOT NULL,
    impressionable_type character varying(255),
    impressionable_id integer,
    user_id integer,
    controller_name character varying(255),
    action_name character varying(255),
    view_name character varying(255),
    request_hash character varying(255),
    session_hash character varying(255),
    ip_address character varying(255),
    message character varying(255),
    referrer text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.impressions OWNER TO tulp;

--
-- Name: impressions_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE impressions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.impressions_id_seq OWNER TO tulp;

--
-- Name: impressions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE impressions_id_seq OWNED BY impressions.id;


--
-- Name: intentions; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE intentions (
    id integer NOT NULL,
    business_id integer NOT NULL,
    user_id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.intentions OWNER TO tulp;

--
-- Name: intentions_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE intentions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.intentions_id_seq OWNER TO tulp;

--
-- Name: intentions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE intentions_id_seq OWNED BY intentions.id;


--
-- Name: letters; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE letters (
    id integer NOT NULL,
    subject character varying(255),
    audience character varying(255),
    text text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.letters OWNER TO tulp;

--
-- Name: letters_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE letters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.letters_id_seq OWNER TO tulp;

--
-- Name: letters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE letters_id_seq OWNED BY letters.id;


--
-- Name: locations; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE locations (
    id integer NOT NULL,
    user_id integer,
    address_street character varying(255),
    address_house character varying(255),
    address_part character varying(255),
    address_building character varying(255),
    location_type character varying(255),
    lat double precision,
    long double precision,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.locations OWNER TO tulp;

--
-- Name: locations_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE locations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.locations_id_seq OWNER TO tulp;

--
-- Name: locations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE locations_id_seq OWNED BY locations.id;


--
-- Name: logs; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE logs (
    id integer NOT NULL,
    log_type character varying(255) NOT NULL,
    data text NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.logs OWNER TO tulp;

--
-- Name: logs_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.logs_id_seq OWNER TO tulp;

--
-- Name: logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE logs_id_seq OWNED BY logs.id;


--
-- Name: mailings; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE mailings (
    id integer NOT NULL,
    user_id integer,
    city_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    user_type character varying(255)
);


ALTER TABLE public.mailings OWNER TO tulp;

--
-- Name: mailings_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE mailings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.mailings_id_seq OWNER TO tulp;

--
-- Name: mailings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE mailings_id_seq OWNED BY mailings.id;


--
-- Name: messages; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE messages (
    id integer NOT NULL,
    sender_id integer,
    recipient_id integer,
    subject character varying(255),
    body text,
    parent_id character varying(255),
    read_at timestamp without time zone,
    deleted_at timestamp without time zone,
    type character varying(255),
    message_type character varying(255),
    sent_copy boolean DEFAULT false,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    sender_type character varying(255),
    recipient_type character varying(255)
);


ALTER TABLE public.messages OWNER TO tulp;

--
-- Name: messages_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.messages_id_seq OWNER TO tulp;

--
-- Name: messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE messages_id_seq OWNED BY messages.id;


--
-- Name: new_categories; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE new_categories (
    id integer DEFAULT nextval('categories_id_seq'::regclass) NOT NULL,
    name character varying(255),
    prepositional_singular character varying(255),
    prepositional_plural character varying(255),
    translit character varying(255),
    parent_id integer,
    lft integer,
    rgt integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.new_categories OWNER TO tulp;

--
-- Name: newsletters; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE newsletters (
    id integer NOT NULL,
    subject character varying(255),
    body text,
    recipients_type character varying(255),
    recipients text,
    city_id integer,
    state character varying(255),
    user_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    text text,
    date_on date,
    transmitted_at timestamp without time zone
);


ALTER TABLE public.newsletters OWNER TO tulp;

--
-- Name: newsletters_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE newsletters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.newsletters_id_seq OWNER TO tulp;

--
-- Name: newsletters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE newsletters_id_seq OWNED BY newsletters.id;


--
-- Name: notification_settings; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE notification_settings (
    id integer NOT NULL,
    user_id integer,
    wall_message character varying(255),
    private_message character varying(255),
    review_of_favorite_business character varying(255),
    review_from_friend character varying(255),
    review_from_favorite character varying(255),
    comment_on_favorite_review character varying(255),
    comment_on_my_review character varying(255),
    compliment character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    wall_message_sent_at timestamp without time zone,
    private_message_sent_at timestamp without time zone,
    review_of_favorite_business_sent_at timestamp without time zone,
    review_from_friend_sent_at timestamp without time zone,
    review_from_favorite_sent_at timestamp without time zone,
    comment_on_favorite_review_sent_at timestamp without time zone,
    comment_on_my_review_sent_at timestamp without time zone,
    compliment_sent_at timestamp without time zone,
    comment_on_my_comment character varying(255),
    comment_on_my_comment_sent_at timestamp without time zone
);


ALTER TABLE public.notification_settings OWNER TO tulp;

--
-- Name: notification_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE notification_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.notification_settings_id_seq OWNER TO tulp;

--
-- Name: notification_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE notification_settings_id_seq OWNED BY notification_settings.id;


--
-- Name: payments; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE payments (
    id integer NOT NULL,
    user_id integer NOT NULL,
    cents integer DEFAULT 0 NOT NULL,
    type character varying(255),
    transactionid character varying(255),
    note character varying(255),
    status integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    payment_type character varying(255),
    service_type character varying(255),
    service_id integer
);


ALTER TABLE public.payments OWNER TO tulp;

--
-- Name: payments_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE payments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.payments_id_seq OWNER TO tulp;

--
-- Name: payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE payments_id_seq OWNED BY payments.id;


--
-- Name: posts; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE posts (
    id integer NOT NULL,
    title character varying(255),
    text text,
    parent_type character varying(255),
    parent_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.posts OWNER TO tulp;

--
-- Name: posts_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.posts_id_seq OWNER TO tulp;

--
-- Name: posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE posts_id_seq OWNED BY posts.id;


--
-- Name: questions_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE questions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.questions_id_seq OWNER TO tulp;

--
-- Name: questions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE questions_id_seq OWNED BY questions.id;


--
-- Name: rates_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE rates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.rates_id_seq OWNER TO tulp;

--
-- Name: rates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE rates_id_seq OWNED BY rates.id;


--
-- Name: ratings_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE ratings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.ratings_id_seq OWNER TO tulp;

--
-- Name: ratings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE ratings_id_seq OWNED BY ratings.id;


--
-- Name: regions; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE regions (
    id integer NOT NULL,
    name character varying(255),
    country_id integer
);


ALTER TABLE public.regions OWNER TO tulp;

--
-- Name: regions_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE regions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.regions_id_seq OWNER TO tulp;

--
-- Name: regions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE regions_id_seq OWNED BY regions.id;


--
-- Name: review_visits; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE review_visits (
    review_id integer,
    number bigint
);


ALTER TABLE public.review_visits OWNER TO tulp;

--
-- Name: reviews; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE reviews (
    id integer NOT NULL,
    user_id integer,
    business_id integer,
    text text,
    business_rating integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    delta boolean DEFAULT true NOT NULL,
    approved boolean DEFAULT false,
    assets_count integer DEFAULT 0,
    first_create boolean DEFAULT false,
    deleted_at timestamp without time zone,
    press_signature integer DEFAULT 0,
    has_image boolean DEFAULT false NOT NULL,
    thanks_count integer DEFAULT 0 NOT NULL,
    comments_count integer DEFAULT 0 NOT NULL,
    last_edit_at timestamp without time zone,
    popularity integer DEFAULT 0 NOT NULL,
    popular boolean DEFAULT false NOT NULL,
    city_id integer
);


ALTER TABLE public.reviews OWNER TO tulp;

--
-- Name: reviews_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE reviews_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.reviews_id_seq OWNER TO tulp;

--
-- Name: reviews_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE reviews_id_seq OWNED BY reviews.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE schema_migrations (
    version character varying(255) NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO tulp;

--
-- Name: search_queries; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE search_queries (
    id integer NOT NULL,
    query text,
    "where" text,
    city_id integer
);


ALTER TABLE public.search_queries OWNER TO tulp;

--
-- Name: search_queries_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE search_queries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.search_queries_id_seq OWNER TO tulp;

--
-- Name: search_queries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE search_queries_id_seq OWNED BY search_queries.id;


--
-- Name: searched_contacts; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE searched_contacts (
    id integer NOT NULL,
    provider character varying(255),
    user_id integer,
    uid character varying(255)
);


ALTER TABLE public.searched_contacts OWNER TO tulp;

--
-- Name: searched_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE searched_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.searched_contacts_id_seq OWNER TO tulp;

--
-- Name: searched_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE searched_contacts_id_seq OWNED BY searched_contacts.id;


--
-- Name: sent_notifications; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE sent_notifications (
    id integer NOT NULL,
    user_id integer NOT NULL,
    notificable_id integer,
    notificable_type character varying(255),
    activator_id integer,
    verb character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.sent_notifications OWNER TO tulp;

--
-- Name: sent_notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE sent_notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sent_notifications_id_seq OWNER TO tulp;

--
-- Name: sent_notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE sent_notifications_id_seq OWNED BY sent_notifications.id;


--
-- Name: settings; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE settings (
    id integer NOT NULL,
    key character varying(255) NOT NULL,
    value text
);


ALTER TABLE public.settings OWNER TO tulp;

--
-- Name: settings_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.settings_id_seq OWNER TO tulp;

--
-- Name: settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE settings_id_seq OWNED BY settings.id;


--
-- Name: similarities; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE similarities (
    id integer NOT NULL,
    user_id integer NOT NULL,
    similar_user_id integer NOT NULL,
    thanks_count integer DEFAULT 0 NOT NULL,
    reviews_count integer DEFAULT 0 NOT NULL,
    rates_count integer DEFAULT 0 NOT NULL,
    description_presence boolean DEFAULT false NOT NULL
);


ALTER TABLE public.similarities OWNER TO tulp;

--
-- Name: similarities_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE similarities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.similarities_id_seq OWNER TO tulp;

--
-- Name: similarities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE similarities_id_seq OWNED BY similarities.id;


--
-- Name: simple_pictures; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE simple_pictures (
    id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    image_file_name character varying(255),
    image_content_type character varying(255),
    image_file_size integer,
    image_updated_at timestamp without time zone
);


ALTER TABLE public.simple_pictures OWNER TO tulp;

--
-- Name: simple_pictures_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE simple_pictures_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.simple_pictures_id_seq OWNER TO tulp;

--
-- Name: simple_pictures_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE simple_pictures_id_seq OWNED BY simple_pictures.id;


--
-- Name: slugs; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE slugs (
    id integer NOT NULL,
    name character varying(255),
    sluggable_id integer,
    sequence integer DEFAULT 1 NOT NULL,
    sluggable_type character varying(40),
    scope character varying(255),
    created_at timestamp without time zone
);


ALTER TABLE public.slugs OWNER TO tulp;

--
-- Name: slugs_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE slugs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.slugs_id_seq OWNER TO tulp;

--
-- Name: slugs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE slugs_id_seq OWNED BY slugs.id;


--
-- Name: social_links; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE social_links (
    id integer NOT NULL,
    user_id integer,
    provider character varying(255),
    uid character varying(255),
    city_name character varying(255),
    email character varying(255),
    gender character varying(255),
    birthday character varying(255),
    name character varying(255),
    avatar_path character varying(255),
    tulp_uid character varying(255)
);


ALTER TABLE public.social_links OWNER TO tulp;

--
-- Name: social_links_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE social_links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.social_links_id_seq OWNER TO tulp;

--
-- Name: social_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE social_links_id_seq OWNED BY social_links.id;


--
-- Name: subscribers; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE subscribers (
    id integer NOT NULL,
    name character varying(255),
    email character varying(255) NOT NULL,
    confirmation_token character varying(255),
    confirmed boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.subscribers OWNER TO tulp;

--
-- Name: subscribers_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE subscribers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.subscribers_id_seq OWNER TO tulp;

--
-- Name: subscribers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE subscribers_id_seq OWNED BY subscribers.id;


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE subscriptions (
    id integer NOT NULL,
    user_id integer,
    subscribable_id integer,
    subscribable_type character varying(255),
    created_at timestamp without time zone,
    deleted_at timestamp without time zone
);


ALTER TABLE public.subscriptions OWNER TO tulp;

--
-- Name: subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.subscriptions_id_seq OWNER TO tulp;

--
-- Name: subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE subscriptions_id_seq OWNED BY subscriptions.id;


--
-- Name: temp_business_categories; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE temp_business_categories (
    id integer NOT NULL,
    business_id integer,
    category_id integer,
    number integer DEFAULT 0 NOT NULL,
    state character varying(255) DEFAULT 'dirty'::character varying NOT NULL,
    "group" character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.temp_business_categories OWNER TO tulp;

--
-- Name: temp_business_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE temp_business_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.temp_business_categories_id_seq OWNER TO tulp;

--
-- Name: temp_business_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE temp_business_categories_id_seq OWNED BY temp_business_categories.id;


--
-- Name: thanks; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE thanks (
    id integer NOT NULL,
    review_id integer NOT NULL,
    user_id integer,
    created_at timestamp without time zone NOT NULL
);


ALTER TABLE public.thanks OWNER TO tulp;

--
-- Name: user_activities; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE user_activities (
    id integer NOT NULL,
    user_id integer,
    object_item_id integer,
    object_item_type character varying(255),
    verb character varying(255) NOT NULL,
    info character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    score integer DEFAULT 0
);


ALTER TABLE public.user_activities OWNER TO tulp;

--
-- Name: user_activities_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE user_activities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.user_activities_id_seq OWNER TO tulp;

--
-- Name: user_activities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE user_activities_id_seq OWNED BY user_activities.id;


--
-- Name: user_alerts; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE user_alerts (
    id integer NOT NULL,
    user_id integer,
    alertable_id integer,
    alertable_type character varying(255),
    item_owner_id integer,
    alert_type character varying(255),
    cache text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    status character varying(255) DEFAULT 'new'::character varying NOT NULL
);


ALTER TABLE public.user_alerts OWNER TO tulp;

--
-- Name: user_alerts_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE user_alerts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.user_alerts_id_seq OWNER TO tulp;

--
-- Name: user_alerts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE user_alerts_id_seq OWNED BY user_alerts.id;


--
-- Name: user_compliments; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE user_compliments (
    id integer NOT NULL,
    creator_id integer NOT NULL,
    user_id integer NOT NULL,
    complimentable_id integer NOT NULL,
    complimentable_type character varying(255) NOT NULL,
    compliment_type character varying(255) NOT NULL,
    message text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    state character varying(255) DEFAULT 'new'::character varying NOT NULL
);


ALTER TABLE public.user_compliments OWNER TO tulp;

--
-- Name: user_compliments_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE user_compliments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.user_compliments_id_seq OWNER TO tulp;

--
-- Name: user_compliments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE user_compliments_id_seq OWNED BY user_compliments.id;


--
-- Name: user_messages; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE user_messages (
    id integer NOT NULL,
    sender_id integer NOT NULL,
    recipient_id integer NOT NULL,
    state character varying(255) NOT NULL,
    body text NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.user_messages OWNER TO tulp;

--
-- Name: user_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE user_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.user_messages_id_seq OWNER TO tulp;

--
-- Name: user_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE user_messages_id_seq OWNED BY user_messages.id;


--
-- Name: user_notification_settings; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE user_notification_settings (
    user_id integer NOT NULL,
    settings text
);


ALTER TABLE public.user_notification_settings OWNER TO tulp;

--
-- Name: user_ratings; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE user_ratings (
    id integer NOT NULL,
    rating_id integer,
    user_id integer,
    score integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.user_ratings OWNER TO tulp;

--
-- Name: user_ratings_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE user_ratings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.user_ratings_id_seq OWNER TO tulp;

--
-- Name: user_ratings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE user_ratings_id_seq OWNED BY user_ratings.id;


--
-- Name: user_statistics; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE user_statistics (
    user_id integer NOT NULL,
    visitors integer DEFAULT 0 NOT NULL,
    visitors_last_month integer DEFAULT 0 NOT NULL,
    reviews integer DEFAULT 0 NOT NULL,
    reviews_last_month integer DEFAULT 0 NOT NULL,
    thanks integer DEFAULT 0 NOT NULL,
    thanks_last_month integer DEFAULT 0 NOT NULL,
    comments integer DEFAULT 0 NOT NULL,
    comments_last_month integer DEFAULT 0 NOT NULL,
    given_comments integer DEFAULT 0 NOT NULL,
    given_comments_last_month integer DEFAULT 0 NOT NULL,
    subscribers integer DEFAULT 0 NOT NULL,
    subscribers_last_month integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    rate1 integer DEFAULT 0 NOT NULL,
    rate2 integer DEFAULT 0 NOT NULL,
    rate3 integer DEFAULT 0 NOT NULL,
    rate4 integer DEFAULT 0 NOT NULL,
    rate5 integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.user_statistics OWNER TO tulp;

--
-- Name: users; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE users (
    id integer NOT NULL,
    email character varying(255) DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying(128) DEFAULT ''::character varying NOT NULL,
    password_salt character varying(255) DEFAULT ''::character varying NOT NULL,
    confirmation_token character varying(255),
    confirmed_at timestamp without time zone,
    confirmation_sent_at timestamp without time zone,
    reset_password_token character varying(255),
    sign_in_count integer DEFAULT 0,
    current_sign_in_at timestamp without time zone,
    last_sign_in_at timestamp without time zone,
    current_sign_in_ip character varying(255),
    last_sign_in_ip character varying(255),
    login character varying(255),
    first_name character varying(255),
    last_name character varying(255),
    gender character varying(1),
    birthday date,
    city_id integer,
    public_email character varying(255),
    description text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    delta boolean DEFAULT true NOT NULL,
    roles_mask integer DEFAULT 0,
    allowed_viewers character varying(255) DEFAULT 'all'::character varying,
    assets_count integer DEFAULT 0,
    rating integer DEFAULT 0,
    time_zone character varying(255),
    approved boolean DEFAULT false NOT NULL,
    deleted_at timestamp without time zone,
    expert boolean DEFAULT false,
    twitter_token character varying(255),
    twitter_secret character varying(255),
    balance_cents integer DEFAULT 0 NOT NULL,
    pressmanager_id integer,
    yandex_wallet_id character varying(255),
    is_proper boolean DEFAULT true,
    twitter character varying(255),
    reset_login_token character varying(255),
    reviews_count integer DEFAULT 0 NOT NULL,
    thanks_count integer DEFAULT 0 NOT NULL,
    name character varying(255),
    comments_count integer DEFAULT 0 NOT NULL,
    birthday_visible character varying(255) DEFAULT 'all'::character varying NOT NULL,
    show_warning_page boolean DEFAULT false NOT NULL,
    last_updates_view_at timestamp without time zone,
    referer_code character varying(255),
    referer_id integer,
    remember_token character varying(255),
    remember_created_at timestamp without time zone
);


ALTER TABLE public.users OWNER TO tulp;

--
-- Name: users_businesses; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE users_businesses (
    business_id integer,
    user_id integer
);


ALTER TABLE public.users_businesses OWNER TO tulp;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO tulp;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE users_id_seq OWNED BY users.id;


--
-- Name: visits; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE visits (
    id integer NOT NULL,
    owner_id integer,
    visitor_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.visits OWNER TO tulp;

--
-- Name: visits_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE visits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.visits_id_seq OWNER TO tulp;

--
-- Name: visits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE visits_id_seq OWNED BY visits.id;


--
-- Name: votes_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE votes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.votes_id_seq OWNER TO tulp;

--
-- Name: votes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE votes_id_seq OWNED BY thanks.id;


--
-- Name: working_days; Type: TABLE; Schema: public; Owner: tulp; Tablespace: 
--

CREATE TABLE working_days (
    id integer NOT NULL,
    business_id integer NOT NULL,
    day integer NOT NULL,
    "from" time without time zone NOT NULL,
    "to" time without time zone NOT NULL
);


ALTER TABLE public.working_days OWNER TO tulp;

--
-- Name: working_days_id_seq; Type: SEQUENCE; Schema: public; Owner: tulp
--

CREATE SEQUENCE working_days_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.working_days_id_seq OWNER TO tulp;

--
-- Name: working_days_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: tulp
--

ALTER SEQUENCE working_days_id_seq OWNED BY working_days.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE answers ALTER COLUMN id SET DEFAULT nextval('answers_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE assets ALTER COLUMN id SET DEFAULT nextval('assets_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE attachings ALTER COLUMN id SET DEFAULT nextval('attachings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE authentications ALTER COLUMN id SET DEFAULT nextval('authentications_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE banners ALTER COLUMN id SET DEFAULT nextval('banners_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE battle_requests ALTER COLUMN id SET DEFAULT nextval('battle_requests_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE battle_users ALTER COLUMN id SET DEFAULT nextval('battle_users_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE battle_votes ALTER COLUMN id SET DEFAULT nextval('battle_votes_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE battles ALTER COLUMN id SET DEFAULT nextval('battles_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE business_categories ALTER COLUMN id SET DEFAULT nextval('business_categories_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE business_owners ALTER COLUMN id SET DEFAULT nextval('business_owners_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE business_ratings ALTER COLUMN id SET DEFAULT nextval('business_ratings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE businesses ALTER COLUMN id SET DEFAULT nextval('businesses_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE categories ALTER COLUMN id SET DEFAULT nextval('categories_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE category_assignments ALTER COLUMN id SET DEFAULT nextval('category_assignments_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE category_ranks ALTER COLUMN id SET DEFAULT nextval('category_ranks_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE choices ALTER COLUMN id SET DEFAULT nextval('choices_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE cities ALTER COLUMN id SET DEFAULT nextval('cities_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE comments ALTER COLUMN id SET DEFAULT nextval('comments_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE contacts ALTER COLUMN id SET DEFAULT nextval('contacts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE countries ALTER COLUMN id SET DEFAULT nextval('countries_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE emails ALTER COLUMN id SET DEFAULT nextval('emails_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE entries ALTER COLUMN id SET DEFAULT nextval('entries_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE exports ALTER COLUMN id SET DEFAULT nextval('exports_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE favorites ALTER COLUMN id SET DEFAULT nextval('favorites_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE favouriteships ALTER COLUMN id SET DEFAULT nextval('favouriteships_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE feedbacks ALTER COLUMN id SET DEFAULT nextval('feedbacks_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE friendship_requests ALTER COLUMN id SET DEFAULT nextval('friendship_requests_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE friendships ALTER COLUMN id SET DEFAULT nextval('friendships_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE gas ALTER COLUMN id SET DEFAULT nextval('gas_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE impressions ALTER COLUMN id SET DEFAULT nextval('impressions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE intentions ALTER COLUMN id SET DEFAULT nextval('intentions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE letters ALTER COLUMN id SET DEFAULT nextval('letters_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE locations ALTER COLUMN id SET DEFAULT nextval('locations_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE logs ALTER COLUMN id SET DEFAULT nextval('logs_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE mailings ALTER COLUMN id SET DEFAULT nextval('mailings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE messages ALTER COLUMN id SET DEFAULT nextval('messages_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE newsletters ALTER COLUMN id SET DEFAULT nextval('newsletters_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE notification_settings ALTER COLUMN id SET DEFAULT nextval('notification_settings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE payments ALTER COLUMN id SET DEFAULT nextval('payments_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE posts ALTER COLUMN id SET DEFAULT nextval('posts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE questions ALTER COLUMN id SET DEFAULT nextval('questions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE rates ALTER COLUMN id SET DEFAULT nextval('rates_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE ratings ALTER COLUMN id SET DEFAULT nextval('ratings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE regions ALTER COLUMN id SET DEFAULT nextval('regions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE reviews ALTER COLUMN id SET DEFAULT nextval('reviews_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE search_queries ALTER COLUMN id SET DEFAULT nextval('search_queries_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE searched_contacts ALTER COLUMN id SET DEFAULT nextval('searched_contacts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE sent_notifications ALTER COLUMN id SET DEFAULT nextval('sent_notifications_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE settings ALTER COLUMN id SET DEFAULT nextval('settings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE similarities ALTER COLUMN id SET DEFAULT nextval('similarities_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE simple_pictures ALTER COLUMN id SET DEFAULT nextval('simple_pictures_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE slugs ALTER COLUMN id SET DEFAULT nextval('slugs_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE social_links ALTER COLUMN id SET DEFAULT nextval('social_links_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE subscribers ALTER COLUMN id SET DEFAULT nextval('subscribers_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE subscriptions ALTER COLUMN id SET DEFAULT nextval('subscriptions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE temp_business_categories ALTER COLUMN id SET DEFAULT nextval('temp_business_categories_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE thanks ALTER COLUMN id SET DEFAULT nextval('votes_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE user_activities ALTER COLUMN id SET DEFAULT nextval('user_activities_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE user_alerts ALTER COLUMN id SET DEFAULT nextval('user_alerts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE user_compliments ALTER COLUMN id SET DEFAULT nextval('user_compliments_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE user_messages ALTER COLUMN id SET DEFAULT nextval('user_messages_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE user_ratings ALTER COLUMN id SET DEFAULT nextval('user_ratings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE users ALTER COLUMN id SET DEFAULT nextval('users_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE visits ALTER COLUMN id SET DEFAULT nextval('visits_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: tulp
--

ALTER TABLE working_days ALTER COLUMN id SET DEFAULT nextval('working_days_id_seq'::regclass);


SET search_path = oldtulp, pg_catalog;

--
-- Name: attribute_types_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY attribute_types
    ADD CONSTRAINT attribute_types_pkey PRIMARY KEY (id);


--
-- Name: business_votes_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY business_votes
    ADD CONSTRAINT business_votes_pkey PRIMARY KEY (id);


--
-- Name: businesses_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY businesses
    ADD CONSTRAINT businesses_pkey PRIMARY KEY (id);


--
-- Name: categories_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: cities2_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY cities2
    ADD CONSTRAINT cities2_pkey PRIMARY KEY (name);


--
-- Name: cities_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY cities
    ADD CONSTRAINT cities_pkey PRIMARY KEY (id);


--
-- Name: comments_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);


--
-- Name: compliment_types_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY compliment_types
    ADD CONSTRAINT compliment_types_pkey PRIMARY KEY (id);


--
-- Name: compliments_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY compliments
    ADD CONSTRAINT compliments_pkey PRIMARY KEY (id);


--
-- Name: event_categories_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY event_categories
    ADD CONSTRAINT event_categories_pkey PRIMARY KEY (id);


--
-- Name: events_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: fan_favs_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY fan_favs
    ADD CONSTRAINT fan_favs_pkey PRIMARY KEY (id);


--
-- Name: feedbacks_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY feedbacks
    ADD CONSTRAINT feedbacks_pkey PRIMARY KEY (id);


--
-- Name: memberships_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: moderation_events_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY moderation_events
    ADD CONSTRAINT moderation_events_pkey PRIMARY KEY (id);


--
-- Name: moderators_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY moderators
    ADD CONSTRAINT moderators_pkey PRIMARY KEY (id);


--
-- Name: photos_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY photos
    ADD CONSTRAINT photos_pkey PRIMARY KEY (id);


--
-- Name: private_messages_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY private_messages
    ADD CONSTRAINT private_messages_pkey PRIMARY KEY (id);


--
-- Name: review_questions_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY review_questions
    ADD CONSTRAINT review_questions_pkey PRIMARY KEY (id);


--
-- Name: review_votes_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY review_votes
    ADD CONSTRAINT review_votes_pkey PRIMARY KEY (id);


--
-- Name: reviews_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);


--
-- Name: tulpers_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY tulpers
    ADD CONSTRAINT tulpers_pkey PRIMARY KEY (id);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: oldtulp; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


SET search_path = public, pg_catalog;

--
-- Name: answers_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY answers
    ADD CONSTRAINT answers_pkey PRIMARY KEY (id);


--
-- Name: assets_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY assets
    ADD CONSTRAINT assets_pkey PRIMARY KEY (id);


--
-- Name: attachings_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY attachings
    ADD CONSTRAINT attachings_pkey PRIMARY KEY (id);


--
-- Name: authentications_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY authentications
    ADD CONSTRAINT authentications_pkey PRIMARY KEY (id);


--
-- Name: banners_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY banners
    ADD CONSTRAINT banners_pkey PRIMARY KEY (id);


--
-- Name: battle_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY battle_requests
    ADD CONSTRAINT battle_requests_pkey PRIMARY KEY (id);


--
-- Name: battle_users_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY battle_users
    ADD CONSTRAINT battle_users_pkey PRIMARY KEY (id);


--
-- Name: battle_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY battle_votes
    ADD CONSTRAINT battle_votes_pkey PRIMARY KEY (id);


--
-- Name: battles_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY battles
    ADD CONSTRAINT battles_pkey PRIMARY KEY (id);


--
-- Name: business_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY business_categories
    ADD CONSTRAINT business_categories_pkey PRIMARY KEY (id);


--
-- Name: business_owners_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY business_owners
    ADD CONSTRAINT business_owners_pkey PRIMARY KEY (id);


--
-- Name: business_ratings_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY business_ratings
    ADD CONSTRAINT business_ratings_pkey PRIMARY KEY (id);


--
-- Name: businesses_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY businesses
    ADD CONSTRAINT businesses_pkey PRIMARY KEY (id);


--
-- Name: categories_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: category_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY category_assignments
    ADD CONSTRAINT category_assignments_pkey PRIMARY KEY (id);


--
-- Name: category_ranks_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY category_ranks
    ADD CONSTRAINT category_ranks_pkey PRIMARY KEY (id);


--
-- Name: choices_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY choices
    ADD CONSTRAINT choices_pkey PRIMARY KEY (id);


--
-- Name: cities_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY cities
    ADD CONSTRAINT cities_pkey PRIMARY KEY (id);


--
-- Name: comments_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);


--
-- Name: contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (id);


--
-- Name: countries_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY countries
    ADD CONSTRAINT countries_pkey PRIMARY KEY (id);


--
-- Name: emails_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY emails
    ADD CONSTRAINT emails_pkey PRIMARY KEY (id);


--
-- Name: entries_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY entries
    ADD CONSTRAINT entries_pkey PRIMARY KEY (id);


--
-- Name: exports_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY exports
    ADD CONSTRAINT exports_pkey PRIMARY KEY (id);


--
-- Name: facts_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY facts
    ADD CONSTRAINT facts_pkey PRIMARY KEY (answer_id);


--
-- Name: favorites_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY favorites
    ADD CONSTRAINT favorites_pkey PRIMARY KEY (id);


--
-- Name: favouriteships_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY favouriteships
    ADD CONSTRAINT favouriteships_pkey PRIMARY KEY (id);


--
-- Name: feedbacks_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY feedbacks
    ADD CONSTRAINT feedbacks_pkey PRIMARY KEY (id);


--
-- Name: friendship_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY friendship_requests
    ADD CONSTRAINT friendship_requests_pkey PRIMARY KEY (id);


--
-- Name: friendships_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY friendships
    ADD CONSTRAINT friendships_pkey PRIMARY KEY (id);


--
-- Name: gas_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY gas
    ADD CONSTRAINT gas_pkey PRIMARY KEY (id);


--
-- Name: impressions_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY impressions
    ADD CONSTRAINT impressions_pkey PRIMARY KEY (id);


--
-- Name: intentions_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY intentions
    ADD CONSTRAINT intentions_pkey PRIMARY KEY (id);


--
-- Name: letters_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY letters
    ADD CONSTRAINT letters_pkey PRIMARY KEY (id);


--
-- Name: locations_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY locations
    ADD CONSTRAINT locations_pkey PRIMARY KEY (id);


--
-- Name: logs_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY logs
    ADD CONSTRAINT logs_pkey PRIMARY KEY (id);


--
-- Name: mailings_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY mailings
    ADD CONSTRAINT mailings_pkey PRIMARY KEY (id);


--
-- Name: messages_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: new_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY new_categories
    ADD CONSTRAINT new_categories_pkey PRIMARY KEY (id);


--
-- Name: newsletters_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY newsletters
    ADD CONSTRAINT newsletters_pkey PRIMARY KEY (id);


--
-- Name: notification_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY notification_settings
    ADD CONSTRAINT notification_settings_pkey PRIMARY KEY (id);


--
-- Name: payments_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: posts_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: questions_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY questions
    ADD CONSTRAINT questions_pkey PRIMARY KEY (id);


--
-- Name: rates_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY rates
    ADD CONSTRAINT rates_pkey PRIMARY KEY (id);


--
-- Name: ratings_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY ratings
    ADD CONSTRAINT ratings_pkey PRIMARY KEY (id);


--
-- Name: regions_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY regions
    ADD CONSTRAINT regions_pkey PRIMARY KEY (id);


--
-- Name: reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);


--
-- Name: search_queries_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY search_queries
    ADD CONSTRAINT search_queries_pkey PRIMARY KEY (id);


--
-- Name: searched_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY searched_contacts
    ADD CONSTRAINT searched_contacts_pkey PRIMARY KEY (id);


--
-- Name: sent_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY sent_notifications
    ADD CONSTRAINT sent_notifications_pkey PRIMARY KEY (id);


--
-- Name: settings_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (id);


--
-- Name: similarities_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY similarities
    ADD CONSTRAINT similarities_pkey PRIMARY KEY (id);


--
-- Name: simple_pictures_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY simple_pictures
    ADD CONSTRAINT simple_pictures_pkey PRIMARY KEY (id);


--
-- Name: slugs_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY slugs
    ADD CONSTRAINT slugs_pkey PRIMARY KEY (id);


--
-- Name: social_links_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY social_links
    ADD CONSTRAINT social_links_pkey PRIMARY KEY (id);


--
-- Name: subscribers_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY subscribers
    ADD CONSTRAINT subscribers_pkey PRIMARY KEY (id);


--
-- Name: subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: temp_business_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY temp_business_categories
    ADD CONSTRAINT temp_business_categories_pkey PRIMARY KEY (id);


--
-- Name: user_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY user_activities
    ADD CONSTRAINT user_activities_pkey PRIMARY KEY (id);


--
-- Name: user_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY user_alerts
    ADD CONSTRAINT user_alerts_pkey PRIMARY KEY (id);


--
-- Name: user_compliments_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY user_compliments
    ADD CONSTRAINT user_compliments_pkey PRIMARY KEY (id);


--
-- Name: user_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY user_messages
    ADD CONSTRAINT user_messages_pkey PRIMARY KEY (id);


--
-- Name: user_notification_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY user_notification_settings
    ADD CONSTRAINT user_notification_settings_pkey PRIMARY KEY (user_id);


--
-- Name: user_ratings_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY user_ratings
    ADD CONSTRAINT user_ratings_pkey PRIMARY KEY (id);


--
-- Name: user_statistics_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY user_statistics
    ADD CONSTRAINT user_statistics_pkey PRIMARY KEY (user_id);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: visits_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY visits
    ADD CONSTRAINT visits_pkey PRIMARY KEY (id);


--
-- Name: votes_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY thanks
    ADD CONSTRAINT votes_pkey PRIMARY KEY (id);


--
-- Name: working_days_pkey; Type: CONSTRAINT; Schema: public; Owner: tulp; Tablespace: 
--

ALTER TABLE ONLY working_days
    ADD CONSTRAINT working_days_pkey PRIMARY KEY (id);


--
-- Name: answers_answerable_id_idx; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX answers_answerable_id_idx ON answers USING btree (answerable_id);


--
-- Name: controlleraction_ip_index; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX controlleraction_ip_index ON impressions USING btree (controller_name, action_name, ip_address);


--
-- Name: controlleraction_request_index; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX controlleraction_request_index ON impressions USING btree (controller_name, action_name, request_hash);


--
-- Name: controlleraction_session_index; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX controlleraction_session_index ON impressions USING btree (controller_name, action_name, session_hash);


--
-- Name: index_assets_on_attachable_id_and_attachable_type; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_assets_on_attachable_id_and_attachable_type ON assets USING btree (attachable_id, attachable_type);


--
-- Name: index_assets_on_review_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_assets_on_review_id ON assets USING btree (review_id) WHERE (review_id IS NOT NULL);


--
-- Name: index_attachings_on_asset_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_attachings_on_asset_id ON attachings USING btree (asset_id);


--
-- Name: index_attachings_on_attachable_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_attachings_on_attachable_id ON attachings USING btree (attachable_id);


--
-- Name: index_battle_requests_on_receiver_uid; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_battle_requests_on_receiver_uid ON battle_requests USING btree (receiver_uid);


--
-- Name: index_battle_requests_on_requester_uid; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_battle_requests_on_requester_uid ON battle_requests USING btree (requester_uid);


--
-- Name: index_battle_users_on_uid; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_battle_users_on_uid ON battle_users USING btree (uid);


--
-- Name: index_battle_votes_on_battle_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_battle_votes_on_battle_id ON battle_votes USING btree (battle_id);


--
-- Name: index_battle_votes_on_user_uid; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_battle_votes_on_user_uid ON battle_votes USING btree (user_uid);


--
-- Name: index_business_ratings_on_business_id_and_rating_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX index_business_ratings_on_business_id_and_rating_id ON business_ratings USING btree (business_id, rating_id);


--
-- Name: index_businesses_on_city_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_businesses_on_city_id ON businesses USING btree (city_id);


--
-- Name: index_categories_on_parent_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_categories_on_parent_id ON categories USING btree (parent_id);


--
-- Name: index_categories_ratings_on_category_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_categories_ratings_on_category_id ON categories_ratings USING btree (category_id);


--
-- Name: index_category_assignments_on_business_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_category_assignments_on_business_id ON category_assignments USING btree (business_id);


--
-- Name: index_category_assignments_on_category_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_category_assignments_on_category_id ON category_assignments USING btree (category_id);


--
-- Name: index_cities_coupons_on_city_id_and_coupon_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX index_cities_coupons_on_city_id_and_coupon_id ON cities_coupons USING btree (city_id, coupon_id);


--
-- Name: index_cities_users_on_user_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_cities_users_on_user_id ON cities_users USING btree (user_id);


--
-- Name: index_contacts_on_user_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_contacts_on_user_id ON contacts USING btree (user_id);


--
-- Name: index_exports_on_business_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX index_exports_on_business_id ON exports USING btree (business_id);


--
-- Name: index_facts_on_business_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_facts_on_business_id ON facts USING btree (business_id);


--
-- Name: index_friendship_requests_on_sender_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_friendship_requests_on_sender_id ON friendship_requests USING btree (sender_id);


--
-- Name: index_friendships_on_user_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_friendships_on_user_id ON friendships USING btree (user_id);


--
-- Name: index_impressions_on_user_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_impressions_on_user_id ON impressions USING btree (user_id);


--
-- Name: index_intentions_on_business_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_intentions_on_business_id ON intentions USING btree (business_id);


--
-- Name: index_intentions_on_user_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_intentions_on_user_id ON intentions USING btree (user_id);


--
-- Name: index_reviews_on_business_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_reviews_on_business_id ON reviews USING btree (business_id);


--
-- Name: index_reviews_on_city_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_reviews_on_city_id ON reviews USING btree (city_id);


--
-- Name: index_reviews_on_user_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_reviews_on_user_id ON reviews USING btree (user_id);


--
-- Name: index_search_queries_on_query_and_where; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_search_queries_on_query_and_where ON search_queries USING btree (query, "where");


--
-- Name: index_settings_on_key; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_settings_on_key ON settings USING btree (key);


--
-- Name: index_similarities_on_user_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_similarities_on_user_id ON similarities USING btree (user_id);


--
-- Name: index_slugs_on_n_s_s_and_s; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX index_slugs_on_n_s_s_and_s ON slugs USING btree (name, sluggable_type, sequence, scope);


--
-- Name: index_slugs_on_sluggable_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_slugs_on_sluggable_id ON slugs USING btree (sluggable_id);


--
-- Name: index_social_links_on_user_id_and_uid_and_provider; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX index_social_links_on_user_id_and_uid_and_provider ON social_links USING btree (user_id, uid, provider);


--
-- Name: index_subscribers_on_confirmation_token; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX index_subscribers_on_confirmation_token ON subscribers USING btree (confirmation_token);


--
-- Name: index_subscribers_on_email; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX index_subscribers_on_email ON subscribers USING btree (email);


--
-- Name: index_subscriptions_on_user_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_subscriptions_on_user_id ON subscriptions USING btree (user_id);


--
-- Name: index_user_activities_on_created_at; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_user_activities_on_created_at ON user_activities USING btree (created_at);


--
-- Name: index_user_activities_on_user_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_user_activities_on_user_id ON user_activities USING btree (user_id);


--
-- Name: index_user_alerts_on_item_owner_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_user_alerts_on_item_owner_id ON user_alerts USING btree (item_owner_id);


--
-- Name: index_user_compliments_on_complimentable; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_user_compliments_on_complimentable ON user_compliments USING btree (complimentable_id, complimentable_type);


--
-- Name: index_user_compliments_on_creator_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_user_compliments_on_creator_id ON user_compliments USING btree (creator_id);


--
-- Name: index_user_compliments_on_user_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_user_compliments_on_user_id ON user_compliments USING btree (user_id);


--
-- Name: index_user_ratings_on_user_id_and_rating_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_user_ratings_on_user_id_and_rating_id ON user_ratings USING btree (user_id, rating_id);


--
-- Name: index_users_on_city_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_users_on_city_id ON users USING btree (city_id);


--
-- Name: index_users_on_confirmation_token; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_confirmation_token ON users USING btree (confirmation_token);


--
-- Name: index_users_on_login; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_login ON users USING btree (login);


--
-- Name: index_users_on_reset_login_token; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_reset_login_token ON users USING btree (reset_login_token);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON users USING btree (reset_password_token);


--
-- Name: index_votes_on_review_id; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX index_votes_on_review_id ON thanks USING btree (review_id);


--
-- Name: poly_ip_index; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX poly_ip_index ON impressions USING btree (impressionable_type, impressionable_id, ip_address);


--
-- Name: poly_request_index; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX poly_request_index ON impressions USING btree (impressionable_type, impressionable_id, request_hash);


--
-- Name: poly_session_index; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX poly_session_index ON impressions USING btree (impressionable_type, impressionable_id, session_hash);


--
-- Name: rates_review_id_idx; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE INDEX rates_review_id_idx ON rates USING btree (review_id);


--
-- Name: review_visits_review_id_idx; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX review_visits_review_id_idx ON review_visits USING btree (review_id);


--
-- Name: unique_schema_migrations; Type: INDEX; Schema: public; Owner: tulp; Tablespace: 
--

CREATE UNIQUE INDEX unique_schema_migrations ON schema_migrations USING btree (version);


--
-- Name: update_business_ratings; Type: TRIGGER; Schema: public; Owner: tulp
--

CREATE TRIGGER update_business_ratings AFTER INSERT OR DELETE ON category_assignments FOR EACH ROW EXECUTE PROCEDURE update_business_ratings();


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

