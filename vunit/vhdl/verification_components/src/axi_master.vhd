-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2014-2024, Lars Asplund lars.anders.asplund@gmail.com
-- Author David Martin david.martin@phios.group


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library osvvm;
use osvvm.RandomPkg.RandomPType;

use work.axi_master_pkg.all;
use work.axi_pkg.all;
use work.axi_slave_private_pkg.check_axi_resp;
use work.axi_slave_private_pkg.check_axi_id;
use work.bus_master_pkg.all;
use work.com_pkg.net;
use work.com_pkg.receive;
use work.com_pkg.reply;
use work.com_types_pkg.all;
use work.log_levels_pkg.all;
use work.logger_pkg.all;
use work.queue_pkg.all;
use work.sync_pkg.all;

entity axi_master is
  generic (
    bus_handle : bus_master_t;
    drive_invalid : boolean := true;
    drive_invalid_val : std_logic := 'X';
    write_high_probability : real range 0.0 to 1.0 := 1.0;
    read_high_probability : real range 0.0 to 1.0 := 1.0
  );
  port (
    aclk : in std_logic;

    arvalid : out std_logic := '0';
    arready : in std_logic;
    arid : out std_logic_vector;
    araddr : out std_logic_vector(address_length(bus_handle) - 1 downto 0) := (others => '0');
    arlen : out std_logic_vector;
    arsize : out std_logic_vector;
    arburst : out axi_burst_type_t;

    rvalid : in std_logic;
    rready : out std_logic := '0';
    rid : in std_logic_vector;
    rdata : in std_logic_vector(data_length(bus_handle) - 1 downto 0);
    rresp : in axi_resp_t;
    rlast : in std_logic;

    awvalid : out std_logic := '0';
    awready : in std_logic := '0';
    awid : out std_logic_vector;
    awaddr : out std_logic_vector(address_length(bus_handle) - 1 downto 0) := (others => '0');
    awlen : out std_logic_vector;
    awsize : out std_logic_vector;
    awburst : out axi_burst_type_t;

    wvalid : out std_logic;
    wready : in std_logic := '0';
    wdata : out std_logic_vector(data_length(bus_handle) - 1 downto 0) := (others => '0');
    wstrb : out std_logic_vector(byte_enable_length(bus_handle) - 1 downto 0) := (others => '0');
    wlast : out std_logic;

    bvalid : in std_logic;
    bready : out std_logic := '0';
    bid : in std_logic_vector;
    bresp : in axi_resp_t := axi_resp_okay
  );
end entity;

architecture a of axi_master is
  constant read_reply_queue, write_reply_queue, message_queue : queue_t := new_queue;
  constant read_addr_queue, read_resp_queue, read_id_queue, read_len_queue : queue_t := new_queue;
  constant write_addr_queue, write_resp_queue, write_id_queue, write_data_queue : queue_t := new_queue;
  signal idle : boolean := true;
begin

  main : process
    variable request_msg : msg_t;
    variable msg_type : msg_type_t;
  begin
    receive(net, bus_handle.p_actor, request_msg);
    msg_type := message_type(request_msg);

    if is_read(msg_type) or is_write(msg_type) then
      push(message_queue, request_msg);
    elsif msg_type = wait_until_idle_msg then
      if not idle or not is_empty(message_queue) then
        wait until idle and is_empty(message_queue) and rising_edge(aclk);
      end if;
      handle_wait_until_idle(net, msg_type, request_msg);
    else
      unexpected_msg_type(msg_type);
    end if;
  end process;

  -- Use separate process to always align to rising edge of clock
  bus_process : process
    procedure drive_ar_invalid is
    begin
      if drive_invalid then
        araddr <= (araddr'range => drive_invalid_val);
        arlen <= (arlen'range => drive_invalid_val);
        arsize <= (arsize'range => drive_invalid_val);
        arburst <= (arburst'range => drive_invalid_val);
        arid <= (arid'range => drive_invalid_val);
      end if;
    end procedure;

    procedure drive_aw_invalid is
    begin
      if drive_invalid then
        awaddr <= (awaddr'range => drive_invalid_val);
        awlen <= (awlen'range => drive_invalid_val);
        awsize <= (awsize'range => drive_invalid_val);
        awburst <= (awburst'range => drive_invalid_val);
        awid <= (arid'range => drive_invalid_val);
      end if;
    end procedure;

    procedure drive_w_invalid is
    begin
      if drive_invalid then
        wlast <= drive_invalid_val;
        wdata <= (wdata'range => drive_invalid_val);
        wstrb <= (wstrb'range => drive_invalid_val);
      end if;
    end procedure;

    variable rnd : RandomPType;
    variable request_msg : msg_t;
    variable msg_type : msg_type_t;
    variable w_done, aw_done : boolean;

    -- These variables are needed to keep the values for logging when transaction is fully done
    variable addr : std_logic_vector(awaddr'range) := (others => '0');
    variable data : std_logic_vector(wdata'range) := (others => '0');
    variable id : std_logic_vector(rid'range) := (others => '0');
    variable len : std_logic_vector(arlen'range) := (others => '0');
    variable burst : positive;
    variable resp : axi_resp_t;
  begin
    -- Initialization
    rnd.InitSeed(rnd'instance_name);
    drive_ar_invalid;
    drive_aw_invalid;
    drive_w_invalid;

    loop
      wait until rising_edge(aclk) and not is_empty(message_queue);
      idle <= false;
      wait for 0 ps;

      request_msg := pop(message_queue);
      msg_type := message_type(request_msg);

      if is_read(msg_type) then
        while rnd.Uniform(0.0, 1.0) > read_high_probability loop
          wait until rising_edge(aclk);
        end loop;
        
        addr := pop_std_ulogic_vector(request_msg);
        araddr <= addr;

        if msg_type = bus_read_msg then 
          arlen(arlen'range) <= (others => '0');
          arsize(arsize'range) <= (others => '0');
          arburst(arburst'range) <= (others => '0');
          arid(arid'range) <= (others => '0');
        elsif msg_type = bus_burst_read_msg then 
          burst := pop_integer(request_msg);
          arlen <= std_logic_vector(to_unsigned(burst, arlen'length));
          arsize(arsize'range) <= (others => '0');
          arburst(arburst'range) <= (others => '0');
          arid(arid'range) <= (others => '0');
        elsif msg_type = axi_read_msg then 
          arlen(arlen'range) <= (others => '0');
          arsize <= pop_std_ulogic_vector(request_msg);
          arburst(arburst'range) <= (others => '0');
          id := pop_std_ulogic_vector(request_msg)(arid'length -1 downto 0);
          arid <= id;
          push(read_id_queue, id);
        elsif msg_type = axi_burst_read_msg then 
          len := pop_std_ulogic_vector(request_msg);
          arlen <= len;
          arsize <= pop_std_ulogic_vector(request_msg);
          arburst <= pop_std_ulogic_vector(request_msg);
          id := pop_std_ulogic_vector(request_msg)(arid'length -1 downto 0);
          arid <= id;
          push(read_id_queue, id);
        end if;

        resp := pop_std_ulogic_vector(request_msg) when is_axi_msg(msg_type) else axi_resp_okay;

        push(read_addr_queue, addr);
        push(read_resp_queue, resp);
        push(read_reply_queue, request_msg);

        arvalid <= '1';
        wait until (arvalid and arready) = '1' and rising_edge(aclk);
        arvalid <= '0';
        drive_ar_invalid;

      elsif is_write(msg_type) then
        while rnd.Uniform(0.0, 1.0) > write_high_probability loop
          wait until rising_edge(aclk);
        end loop;
        addr := pop_std_ulogic_vector(request_msg);
        awaddr <= addr;
        data := pop_std_ulogic_vector(request_msg);
        wdata <= data;
        wstrb <= pop_std_ulogic_vector(request_msg);

        if(is_axi_msg(msg_type)) then 
          awlen <= pop_std_ulogic_vector(request_msg);
          awsize <= pop_std_ulogic_vector(request_msg);
          awburst <= pop_std_ulogic_vector(request_msg);

          id := pop_std_ulogic_vector(request_msg)(awid'length -1 downto 0);
          awid <= id;
          push(write_id_queue, id);

          wlast <= pop_std_ulogic(request_msg);
        end if;

        resp := pop_std_ulogic_vector(request_msg) when is_axi_msg(msg_type) else axi_resp_okay;
        
        push(write_data_queue, data);
        push(write_addr_queue, addr);
        push(write_resp_queue, resp);
        push(write_reply_queue, request_msg);

        wvalid <= '1';
        awvalid <= '1';

        w_done := false;
        aw_done := false;
        while not (w_done and aw_done) loop
          wait until ((awvalid and awready) = '1' or (wvalid and wready) = '1') and rising_edge(aclk);

          if (awvalid and awready) = '1' then
            awvalid <= '0';
            drive_aw_invalid;

            aw_done := true;
          end if;

          if (wvalid and wready) = '1' then
            wvalid <= '0';
            drive_w_invalid;

            w_done := true;
          end if;
        end loop;
      else
        unexpected_msg_type(msg_type);
      end if;

      idle <= true;
    end loop;
  end process;

  -- Reply in separate process do not destroy alignment with the clock
  read_reply : process
    variable request_msg, reply_msg : msg_t;
    variable msg_type : msg_type_t;
    variable addr : std_logic_vector(araddr'range) := (others => '0');
    variable resp : axi_resp_t;
    variable id : std_logic_vector(rid'range) := (others => '0');
  begin
    
    rready <= '1';
    wait until (rvalid and rready) = '1' and rising_edge(aclk);
    rready <= '0';

    reply_msg := new_msg;
    request_msg := pop(read_reply_queue);
    msg_type := message_type(request_msg);
    addr := pop(read_addr_queue);
    resp := pop(read_resp_queue);

    if msg_type = bus_read_msg then 

    elsif msg_type = bus_burst_read_msg then 

    elsif msg_type = axi_read_msg then 
      id := pop(read_id_queue);
      check_axi_id(bus_handle, rid, id, "rid");
    elsif msg_type = axi_burst_read_msg then 
      id := pop(read_id_queue);
      check_axi_id(bus_handle, rid, id, "rid");
    end if;

    check_axi_resp(bus_handle, rresp, resp, "rresp");

    if is_visible(bus_handle.p_logger, debug) then
      debug(bus_handle.p_logger,
            "Read 0x" & to_hstring(rdata) &
              " from address 0x" & to_hstring(addr));
    end if;
    
    push_std_ulogic_vector(reply_msg, rdata);
    reply(net, request_msg, reply_msg);
    delete(request_msg);
  end process;

  -- Reply in separate process do not destroy alignment with the clock
  write_reply : process
    variable request_msg, reply_msg : msg_t;
    variable msg_type : msg_type_t;
    variable addr : std_logic_vector(awaddr'range) := (others => '0');
    variable data : std_logic_vector(wdata'range) := (others => '0');
    variable resp : axi_resp_t;
    variable id : std_logic_vector(rid'range) := (others => '0');
  begin
    
    bready <= '1';
    wait until (bvalid and bready) = '1' and rising_edge(aclk);
    bready <= '0';

    request_msg := pop(write_reply_queue);
    msg_type := message_type(request_msg);
    addr := pop(write_addr_queue);
    data := pop(write_data_queue);
    resp := pop(write_resp_queue);

    if(is_axi_msg(msg_type)) then
      id := pop(write_id_queue);
      check_axi_id(bus_handle, bid, id, "bid");
    end if;

    check_axi_resp(bus_handle, bresp, resp, "bresp");

    if is_visible(bus_handle.p_logger, debug) then
      debug(bus_handle.p_logger,
            "Wrote 0x" & to_hstring(data) &
              " to address 0x" & to_hstring(addr));
    end if;

    delete(request_msg);
  end process;

end architecture;
