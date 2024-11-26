-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2014-2024, Lars Asplund lars.anders.asplund@gmail.com

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.bus_master_pkg.all;
use work.check_pkg.all;
use work.com_pkg.all;
use work.com_types_pkg.all;
use work.queue_pkg.all;
use work.sync_pkg.all;
use work.logger_pkg.all;
use work.vc_pkg.all;
use work.runner_pkg.all;
use work.run_pkg.all;
use work.run_types_pkg.all;
use work.log_levels_pkg.all;
use work.apb_requester_pkg.all;

entity apb_requester is
  generic (
    bus_handle        : apb_requester_t
  );
  port (
    clk                 : in  std_logic;
    reset               : in  std_logic;
    psel_o              : out std_logic;
    penable_o           : out std_logic;
    paddr_o             : out std_logic_vector(address_length(bus_handle.p_bus_handle) - 1 downto 0);
    pwrite_o            : out std_logic;
    pwdata_o            : out std_logic_vector(data_length(bus_handle.p_bus_handle) - 1 downto 0);
    prdata_i            : in  std_logic_vector(data_length(bus_handle.p_bus_handle) - 1 downto 0);
    pready_i            : in  std_logic;
    pslverr_i           : in  std_logic := '0'
  );
end entity;

architecture behav of apb_requester is
  constant message_queue : queue_t := new_queue;
  signal idle_bus : boolean := true;

  impure function queues_empty return boolean is
  begin
    return is_empty(message_queue);
  end function;

  impure function is_idle return boolean is
  begin
    return idle_bus;
  end function;

begin

  PROC_MAIN: process
    variable request_msg : msg_t;
    variable msg_type : msg_type_t;
  begin
    DISPATCH_LOOP : loop
      receive(net, bus_handle.p_bus_handle.p_actor, request_msg);
      msg_type := message_type(request_msg);

      if msg_type = bus_read_msg or msg_type = apb_read_msg
         or msg_type = bus_write_msg or msg_type = apb_write_msg then
        push(message_queue, request_msg);
      elsif msg_type = wait_until_idle_msg then
        if not is_idle or not queues_empty then
          wait until is_idle and queues_empty and rising_edge(clk);
        end if;
        handle_wait_until_idle(net, msg_type, request_msg);
      elsif msg_type = wait_for_time_msg then
        push(message_queue, request_msg);
      else
        if bus_handle.p_unexpected_msg_type_policy = fail then
          unexpected_msg_type(msg_type);
        end if;
      end if;
    end loop;
  end process;

  BUS_PROCESS: process
    procedure drive_bus_invalid is
    begin
      if bus_handle.p_drive_invalid then
        penable_o <= bus_handle.p_drive_invalid_val;
        paddr_o   <= (paddr_o'range => bus_handle.p_drive_invalid_val);
        pwrite_o  <= bus_handle.p_drive_invalid_val;
        pwdata_o  <= (pwdata_o'range => bus_handle.p_drive_invalid_val);
      end if;
    end procedure;

    variable request_msg, reply_msg : msg_t;
    variable msg_type : msg_type_t;
    variable addr_this_transaction : std_logic_vector(paddr_o'range) := (others => '0');
    variable data_this_transaction : std_logic_vector(prdata_i'range) := (others => '0');
    variable byte_enable_this_transaction : std_logic_vector(byte_enable_length(bus_handle)-1 downto 0);
    variable error_this_transaction : std_logic := '0';
    constant key : key_t := get_entry_key(test_runner_cleanup);
  begin
    loop
      drive_bus_invalid;
      psel_o <= '0';

      if is_empty(message_queue) then
        unlock(runner, key);
        wait until rising_edge(clk) and not is_empty(message_queue);
      end if;
      lock(runner, key);
      idle_bus <= false;
      wait for 0 ns;

      request_msg := pop(message_queue);
      msg_type := message_type(request_msg);

      if msg_type = apb_write_msg then
        addr_this_transaction := pop_std_ulogic_vector(request_msg);
        data_this_transaction := pop_std_ulogic_vector(request_msg);
        byte_enable_this_transaction := pop_std_ulogic_vector(request_msg);
        error_this_transaction := pop_std_ulogic(request_msg);

        psel_o <= '1';
        penable_o <= '0';
        pwrite_o <= '1';
        paddr_o <= addr_this_transaction;
        pwdata_o <= data_this_transaction;

        wait until rising_edge(clk);
        penable_o <= '1';
        wait until (pready_i and penable_o) = '1' and rising_edge(clk);

        check_equal(pslverr_i, error_this_transaction, "Unexpected pslverror response for write request.");

        if is_visible(bus_handle.p_bus_handle.p_logger, debug) then
          debug(bus_handle.p_bus_handle.p_logger,
                "Wrote 0x" & to_hstring(data_this_transaction) &
                  " to address 0x" & to_hstring(addr_this_transaction));
        end if;

        reply_msg := new_msg;
        reply(net, request_msg, reply_msg);

      elsif msg_type = apb_read_msg then
        addr_this_transaction := pop_std_ulogic_vector(request_msg);
        error_this_transaction := pop_std_ulogic(request_msg);

        psel_o <= '1';
        penable_o <= '0';
        pwrite_o <= '0';
        paddr_o <= addr_this_transaction;

        wait until rising_edge(clk);
        penable_o <= '1';
        wait until (pready_i and penable_o) = '1' and rising_edge(clk);

        check_equal(pslverr_i, error_this_transaction, "Unexpected pslverror response for read request.");

        reply_msg := new_msg;
        push_std_ulogic_vector(reply_msg, prdata_i);
        reply(net, request_msg, reply_msg);

      elsif msg_type = wait_for_time_msg then
        handle_wait_for_time(net, msg_type, request_msg);
        -- Re-align with the clock when a wait for time message was handled, because this breaks edge alignment.
        wait until rising_edge(clk);
      end if;

      idle_bus <= true;
    end loop;
  end process;
end architecture;
