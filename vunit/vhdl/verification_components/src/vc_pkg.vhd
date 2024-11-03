-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2014-2024, Lars Asplund lars.anders.asplund@gmail.com
--
-- This package contains common functionality for VCs.

context work.vunit_context;
context work.com_context;

package vc_pkg is
  type unexpected_msg_type_policy_t is (fail, ignore);

  type std_cfg_t is record
    p_id : id_t;
    p_actor : actor_t;
    p_logger : logger_t;
    p_checker : checker_t;
    p_unexpected_msg_type_policy : unexpected_msg_type_policy_t;
  end record;

  constant null_std_cfg : std_cfg_t := (
    p_id => null_id,
    p_actor => null_actor,
    p_logger => null_logger,
    p_checker => null_checker,
    p_unexpected_msg_type_policy => ignore
  );

  -- Creates a standard VC configuration with an id, an actor, a logger, a
  -- checker, and an unexpected message type policy.
  --
  -- If id = null_id, the id will be assigned the name provider:vc_name:n where n is 1
  -- for the first instance and increasing with one for every additional instance.
  --
  -- The id must not have an associated actor before the call as that may indicate
  -- several users of the same actor.
  --
  -- If a logger exist for the id, it will be reused. If not, a new logger is created.
  -- A new checker is created that reports to the logger.
  impure function create_std_cfg(
    id : id_t := null_id;
    provider : string := "";
    vc_name : string := "";
    unexpected_msg_type_policy : unexpected_msg_type_policy_t := fail
  ) return std_cfg_t;

  -- These functions extracts information from the standard VC configuration
  impure function get_id(std_cfg : std_cfg_t) return id_t;
  impure function get_actor(std_cfg : std_cfg_t) return actor_t;
  impure function get_logger(std_cfg : std_cfg_t) return logger_t;
  impure function get_checker(std_cfg : std_cfg_t) return checker_t;
  impure function unexpected_msg_type_policy(std_cfg : std_cfg_t) return unexpected_msg_type_policy_t;

  -- Handle messages with unexpected message type according to the standard configuration
  procedure unexpected_msg_type(msg_type : msg_type_t; std_cfg : std_cfg_t);

end package;

package body vc_pkg is
  constant vc_pkg_logger  : logger_t  := get_logger("vunit_lib:vc_pkg");
  constant vc_pkg_checker : checker_t := new_checker(vc_pkg_logger);

  impure function create_std_cfg(
    id : id_t := null_id;
    provider : string := "";
    vc_name : string := "";
    unexpected_msg_type_policy : unexpected_msg_type_policy_t := fail
  ) return std_cfg_t is
    variable result : std_cfg_t;
    variable provider_id : id_t;
    variable vc_id : id_t;
  begin
    if id /= null_id then
      result.p_id := id;
    else
      if provider = "" then
        check_failed(vc_pkg_checker, "A provider must be provided.");

        -- Simplifies testing when vc_pkg_checker logger is mocked
        return null_std_cfg;
      end if;

      if vc_name = "" then
        check_failed(vc_pkg_checker, "A VC name must be provided.");

        -- Simplifies testing when vc_pkg_checker logger is mocked
        return null_std_cfg;
      end if;

      provider_id := get_id(provider);
      vc_id := get_id(vc_name, parent => provider_id);
      result.p_id := get_id(to_string(num_children(vc_id) + 1), parent => vc_id);
    end if;

    result.p_unexpected_msg_type_policy := unexpected_msg_type_policy;

    if find(result.p_id, enable_deferred_creation => false) /= null_actor then
      check_failed(vc_pkg_checker, "An actor already exists for " & full_name(result.p_id) & ".");
    else
      result.p_actor := new_actor(result.p_id);
    end if;

    result.p_logger := get_logger(result.p_id);
    result.p_checker := new_checker(result.p_logger);

    return result;
  end;

  impure function get_id(std_cfg : std_cfg_t) return id_t is
  begin
    return std_cfg.p_id;
  end;

  impure function get_actor(std_cfg : std_cfg_t) return actor_t is
  begin
    return std_cfg.p_actor;
  end;

  impure function get_logger(std_cfg : std_cfg_t) return logger_t is
  begin
    return std_cfg.p_logger;
  end;

  impure function get_checker(std_cfg : std_cfg_t) return checker_t is
  begin
    return std_cfg.p_checker;
  end;

  impure function unexpected_msg_type_policy(std_cfg : std_cfg_t) return unexpected_msg_type_policy_t is
  begin
    return std_cfg.p_unexpected_msg_type_policy;
  end;

  procedure unexpected_msg_type(msg_type : msg_type_t;
                                std_cfg : std_cfg_t) is
  begin
    if unexpected_msg_type_policy(std_cfg) = fail then
      unexpected_msg_type(msg_type, get_logger(std_cfg));
    end if;
  end;
end package body;
