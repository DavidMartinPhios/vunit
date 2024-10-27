.. _vc_user_guide:

Verification Components User Guide
==================================

.. NOTE::
  This library is released as a *BETA* version.
  This means non-backwards compatible changes are still likely based on feedback from our users.

Included verification components (VCs):

- Avalon Memory-Mapped master
- Avalon Memory-Mapped slave
- Avalon Streaming sink
- Avalon Streaming source
- AXI-Lite master
- AXI read slave
- AXI write slave
- AXI stream master
- AXI stream monitor
- AXI stream protocol checker
- AXI stream slave
- RAM master
- Wishbone master
- Wishbone slave
- UART master
- UART slave

In addition to VCs VUnit also has the concept of :ref:`Verification Component Interfaces <verification_component_interfaces>` (VCI).
A single VC typically implements several VCIs.
For example an AXI-lite VC or RAM master VC can support the same generic bus master and synchronization VCI while also
supporting their own bus specific VCIs.

.. TIP::
  The main benefit of generic VCIs is to reduce redundancy between VCs and allow the user to write generic code that
  will work regardless of the specific VC instance used.
  For example control registers might be defined as a RAM-style bus in a submodule but be mapped to an AXI-lite
  interface on the top level.
  The same testbench code for talking to the submodule can be used in both the submodule test bench as well as the top
  level test bench regardless of the fact that two different VCs have been used.
  Without generic VCIs copy pasting the code and changing the type of read/write procedure call would be required.

Neither a VC or a VCI there is the :ref:`memory model <memory_model>` which is a model of a memory space such as the
DRAM address space in a computer system.
The memory mapped slave VCs such as AXI and Wishbone make transactions against the memory model which provides access
permissions, expected data settings as well as the actual buffer for reading and writing data.

.. toctree::
   :maxdepth: 1
   :hidden:

   memory_model

.. _verification_component_interfaces:

Verification Component Interfaces
---------------------------------

A verification component interface (VCI) is a procedural interface to a VC.
A VCI is defined as procedures in a package file.
Several VCs can support the same generic VCI to enable code re-use both for the users and the VC-developers.

List of VCIs included in the main repository:

Included verification component interfaces (VCIs):

* :ref:`Bus master <bus_master_vci>`: generic read and write of bus with address and byte enable.
* :ref:`Stream <stream_vci>`: push and pop of data stream without address.
* :ref:`Synchronization <sync_vci>`: wait for time and events.

.. toctree::
   :maxdepth: 1
   :hidden:

   vci

.. _verification_components:

Verification Components
-----------------------

A verification component (VC) is an entity that is normally connected to the DUT via a bus signal interface such as
AXI-Lite.
The main test sequence in the test bench sends messages to the VCs that will then perform the actual bus signal
transactions.
The benefit of this is both to raise the abstraction level of the test bench as well as making it easy to have parallel
activity on several bus interfaces.

A VC typically has an associated package defining procedures for sending to and receiving messages from the VC.
Each VC instance is associated with a handle that is created in the test bench and set as a generic on the VC
instantiation.
The handle is given as an argument to the procedure calls to direct messages to the specific VC instance.


VC and VCI Compliance Testing
=============================

VUnit establishes a standard for VCs and VCIs, designed around a set of rules that promote flexibility, reusability, interoperability,
and future-proofing of VCs and VCIs.

Rule 1
------

The file containing a VC entity shall include only one entity, and the file containing a VCI package shall include only one package.

**Rationale**: This simplifies compliance testing, as the VC/VCI can be referenced by file name.

Rule 2
------

The function used to create a new instance of a VC (the constructor) shall have a name starting with ``new_``.

**Rationale**: This naming convention allows the compliance test to easily identify the constructor and evaluate it against other applicable rules.

Rule 3
------

A VC constructor shall include an ``id`` parameter, allowing the user to specify the VC's identity.

**Rationale**: This provides users control over the namespace assigned to the VC.

Rule 4
------

The ``id`` parameter shall default to ``null_id``. If not overridden, the ``id`` shall follow the format ``<provider>:<VC name>:<n>``, where
``<n>`` starts at 1 for the first instance of the VC and increments with each subsequent instance.

**Rationale**: This structured format ensures clear identification while preventing name collisions when combining VCs from different providers.

Rule 5
------

All identity-supporting objects associated with the VC (such as loggers, actors, and events) shall be assigned an identity within the namespace
defined by the constructor’s ``id`` parameter.

**Rationale**: This gives users control over these objects and allows for easy association of log messages with a specific VC instance.

Rule 6
------

All checkers used by the VC shall report to the VC’s loggers.

**Rationale**: This ensures that error messages are clearly linked to a specific VC instance.

Rule 7
------

A VC constructor shall include an ``unexpected_msg_type_policy`` parameter, allowing users to define the action taken when the VC receives an unexpected message type.

**Rationale**: A VC actor subscribing to another actor may receive irrelevant messages, while VCs addressed directly should only receive messages they can process.

Rule 10
-------

A VC shall keep the ``test_runner_cleanup`` entry gate locked while it has unfinished work, and must unlock the gate at all other times.

**Rationale**: This prevents premature termination of the testbench.

Rule 11
-------

All fields in the handle returned by the constructor shall begin with the prefix ``p_``.

**Rationale**: This emphasizes that all fields are private, which simplifies future updates without breaking backward compatibility.

Rule 12
-------

The standard configuration, ``std_cfg_t``, consisting of the required parameters for the constructor, shall be accessible through the handle via a ``get_std_cfg`` call.

**Rationale**: This enables reuse of common operations across multiple VCs.

Rule 13
-------

A VC shall only have one generic.

**Rationale**: Representing a VC with a single object simplifies code management. Since all handle fields are private, future updates are less likely to break backward compatibility.

Rule 14
-------

All VCs shall support the sync interface.

**Rationale**: Being able to verify whether a VC is idle and introduce delays between transactions is a common and useful feature for VC users.

Rule 15
-------

A VC shall keep the ``test_runner_cleanup`` phase entry gate locked while there are pending operations.

**Rationale**: Locking the gate prevents the simulation from terminating prematurely.
