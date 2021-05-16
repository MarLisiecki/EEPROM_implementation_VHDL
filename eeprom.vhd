----------------------------------------------------------------------------------
-- Nazwa uk³adu: Komunikacja I2C do pamiêci EEPROM AT24C04 512 s³ów (4kb)
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;


entity eeprom is
-- Generate constans  
   GENERIC
   (
    input_clk : INTEGER := 50_000_000; --clock speed from master [Hz]
    bus_clk   : INTEGER := 400_000   --speed of I2C [Hz]
    );
-- Declaration of in and outs of our MASTER
    port 
    (
       CLK : in std_logic;
       SCL : inout std_logic := 'Z';
       SDA : inout std_logic := 'Z';
       BUTTON_START : in std_logic;
       BUTTON_RESET : in std_logic
    );
end eeprom;

architecture eeprom_architecture of eeprom is

constant divider  :  INTEGER := (input_clk/bus_clk)/4;                                                    --number of clocks in 1/4 cycle of SCL signal
-- State machine for I2C
type i2c_SM IS(idle, start, command, slave_ack_first , write, read, slave_ack_second, master_ack, stop); --machine state
signal i2c_state : i2c_SM;
-- Main state machine
type receive_send_SM_type is (receive_data, send_data, idle);
signal receive_send_SM : receive_send_SM_type := idle;
signal next_receive_send_state: receive_send_SM_type;
-- Signals for I2C implementation
signal slave_address : std_logic_vector (6 downto 0) := "1010000";
signal read_flag : std_logic := '0';
signal data_to_write : std_logic_vector(7 downto 0) := "00000000";
signal busy_flag : std_logic := '0';
signal data_read_from_slave : std_logic_vector := "00000000";  
signal ack_error_flag : std_logic := '0';
signal enable : std_logic := '0'; -- PUT IN MAIN SM
-- Signals for I2C to support communication
signal sda_clk : std_logic;
signal previous_sda_clk :std_logic;
signal scl_clk : std_logic;
signal enable_scl : std_logic := '0';
signal internal_sda : std_logic := '1';
signal enable_internal_sda : std_logic;
signal bit_counter : INTEGER range 0 to 7 :=7;
signal read_or_write : std_logic;
signal slave_address_buffer : std_logic_vector(7 downto 0) := "00000000";
signal word_address : std_logic_vector(7 downto 0) := "00001010";
signal data : std_logic_vector(7 downto 0) := "10101010";
signal busy_cnt : std_logic_vector (3 downto 0) := "0000";
signal busy_flag_prev : std_logic := '0';
signal data : std_logic_vector(7 downto 0);
begin
-- Main state machine 
main_state_machine : process (BUTTON_START, CLK)
    begin
        busy_flag_prev <= busy_flag;
        if (busy_flag_prev = '0' and busy_flag = '1') then
            busy_cnt <= busy_cnt + "01";
        end if;
        if (BUTTON_RESET = '1') then
            
        end if;
        receive_send_SM <= next_receive_send_state;
        case receive_send_SM is
            when idle =>
                if (BUTTON_START'event and BUTTON_START = '1') then
                   next_receive_send_state <= receive_data;      
                end if; 
            when receive_data =>
               case busy_cnt is
                    when "0000" => 
                        enable <= '1';
                        slave_address <= "1010000";
                        read_or_write <= '0';
                        data_to_write <= "00000000";
                    when "0001" => 
                        read_or_write <= '1';
                    when "0010" => 
                        read_or_write <= '0';
                        data_to_write <= "00001010";
                        if (busy_flag ='0') then
                            -- TODO do pliku
                            data(7 downto 0) <=  data_read_from_slave;
                        end if;
                    when "0011" =>
                        read_or_write <= '1';
                    when "" => 
                        enable <= '0';
                        if (busy_flag = '0') then
                            busy_cnt <= "0000";
                            next_receive_send_state <= idle;
                        end if;
                    when others =>
                        null;
                end case;
                        
            when send_data =>
                -- TODO To z pliku
                slave_address <= "1010000";
                data_to_write <= "00000000";
                word_address <=  "00001010";
                enable <= '1';
            when others =>
                    next_receive_send_state <= idle;                         
        end case;    
        end process main_state_machine;


-- CLK generation for transmission - BUS CLOCKING
bus_clocking : process(CLK, BUTTON_RESET)
    variable prescaler_counter : INTEGER range 0 to divider*4;
    begin
        if (BUTTON_RESET = '1') then
            prescaler_counter := 0;
        elsif (rising_edge(CLK)) then
            previous_sda_clk <= sda_clk;
            if (prescaler_counter = divider*4-1) then
                prescaler_counter := 0;
            else 
                prescaler_counter := prescaler_counter + 1;
            end if;
            case prescaler_counter is 
                when 0 to divider-1 =>                    -- SCL line data can't be send
                    scl_clk <= '0';
                    sda_clk <= '0';
                when divider to divider*2-1 =>              -- SCL still low- prepare data to send
                    scl_clk <= '0';
                    sda_clk <= '1';
                when divider to divider*3-1 =>              -- SCL high time to send data
                    scl_clk <= '1';
                    sda_clk <= '0';
                when others =>
                    scl_clk <= '1';
                    sda_clk <= '0';
            end case;  
        end if; 
    end process bus_clocking;
i2c_state_machine : process (CLK, BUTTON_RESET) 
begin
    if(BUTTON_RESET = '1') then
        i2c_state <= idle;
        busy_flag <= '1';
        enable_scl <= '0';
        internal_sda <= '1';
        ack_error_flag <= '0';
        bit_counter <= 7;
        data_read_from_slave <= "00000000";
    elsif(rising_edge(CLK)) then
        if(sda_clk = '1' and previous_sda_clk = '0') then          -- Data can be send
            case i2c_state is
                when idle =>
                    if(enable = '1') then 
                        busy_flag <= '1';
                        slave_address_buffer  <=  slave_address & read_or_write;
                        i2c_state <= start;
                    else 
                        busy_flag <= '0';
                        i2c_state <= idle;
                    end if;
                when start =>
                    busy_flag <= '1';
                    internal_sda <= slave_address_buffer(bit_counter);
                    i2c_state <= command;
                when command =>
                    if(bit_counter = 0) then
                        internal_sda <= '1';
                        bit_counter <= 7;
                        i2c_state <= slave_ack_first;
                    else 
                        bit_counter <= bit_counter - 1;
                        internal_sda <= slave_address_buffer(bit_counter - 1);
                    end if;
                when slave_ack_first =>
                    if(slave_address_buffer(0) = '0') then
                        data_to_write <= word_address;
                        internal_sda <= data_to_write(bit_counter);
                        busy_flag <= '0';
                        i2c_state <= write;
                    else 
                        internal_sda <= '1';
                        i2c_state <= read;
                    end if;
                when write => 
                    busy_flag <= '1';
                    if (bit_counter = 0) then
                        internal_sda <= '1';
                        bit_counter <= 7;
                        i2c_state <= slave_ack_second;
                    else 
                        bit_counter <= bit_counter - 1;
                        internal_sda <= data_to_write(bit_counter-1);
                        i2c_state <= write;
                    end if;
                when read => 
                    busy_flag <= '1';
                    if (bit_counter = 0) then
                        if (enable = '1' and slave_address_buffer = slave_address & read_or_write) then 
                            internal_sda <= '0';
                        else
                            internal_sda <= '1';
                         end if; 
                     bit_counter <= 7;
                     i2c_state <= master_ack;
                     else 
                        bit_counter <= bit_counter-1;
                        i2c_state <= read; 
                    end if;
                when slave_ack_second =>
                    if (enable = '1') then
                        busy_flag <= '0';
                        data_to_write <= data;
                        if (slave_address_buffer = slave_address & read_or_write) then
                            internal_sda <= data_to_write(bit_counter);
                            i2c_state <= write;
                            -- Enable set 0 in main state machine by second busy set to 0
                        end if; 
                    else 
                        i2c_state <= stop;
                    end if;
                when master_ack => 
                    if (enable = '1') then
                        busy_flag <= '0';
                        if (slave_address_buffer = slave_address & read_or_write) then
                            internal_sda <= '1';
                            i2c_state <= read;
                            -- Enable set 0 in main state machine by second busy set to 0
                        end if;
                    else 
                        i2c_state <= stop;
                    end if;
                when stop =>
                    busy_flag <= '0';
                    i2c_state <= idle;
            end case;
        elsif (sda_clk = '0' and previous_sda_clk = '1') then
            case i2c_state is 
                when start =>
                    if(enable_scl = '0') then
                        enable_scl <= '1';
                        ack_error_flag <= '0';
                    end if;
                when slave_ack_first =>
                    if(SDA /= '0' or ack_error_flag = '1') then
                        ack_error_flag <= '0';
                    end if;
                when read =>
                    data_read_from_slave(bit_counter) <= SDA;
                when slave_ack_second =>
                    if(SDA /= '0' or ack_error_flag = '1') then
                        ack_error_flag <= '0';
                    end if;
                when stop => 
                    enable_scl <= '0';
                when others =>
                    null;
            end case;
        end if; 
    end if;
end process i2c_state_machine; 
-- Asynchronus 
with i2c_state select
    enable_internal_sda <= previous_sda_clk when start,    
                 not previous_sda_clk when stop,  
                 internal_sda when others; 
SCL <= '0' when (enable_scl = '1' and scl_clk = '0') else 'Z';
SDA <= '0' when enable_internal_sda = '0' else 'Z';
end architecture eeprom_architecture;
