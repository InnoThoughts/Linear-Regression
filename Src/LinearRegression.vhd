--! @file LinearRegression.vhd
--!
--! @authors	Salvatore Barone <salvator.barone@gmail.com> <br>
--!				Alfonso Di Martino <alfonsodimartino160989@gmail.com> <br>
--!				Sossio Fiorillo <fsossio@gmail.com> <br>
--!				Pietro Liguori <pie.liguori@gmail.com> <br>
--!
--! @date 03 07 2017
--! 
--! @copyright
--! Copyright 2017	Salvatore Barone <salvator.barone@gmail.com> <br>
--!					Alfonso Di Martino <alfonsodimartino160989@gmail.com> <br>
--!					Sossio Fiorillo <fsossio@gmail.com> <br>
--!					Pietro Liguori <pie.liguori@gmail.com> <br>					
--! 
--! This file is part of Linear-Regression.
--! 
--! Linear-Regression is free software; you can redistribute it and/or modify it under the terms of
--! the GNU General Public License as published by the Free Software Foundation; either version 3 of
--! the License, or any later version.
--! 
--! Linear-Regression is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
--! without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
--! GNU General Public License for more details.
--! 
--! You should have received a copy of the GNU General Public License along with this program; if not,
--! write to the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,
--! USA.
--!

--! @addtogroup LinearRegression
--! @{
--! @brief Regressione Lineare in VHDL.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! @mainpage
--! @brief Regressione Lineare.
--! @details
--! Il componente permette di effettuare la regressione lineare.
--!
--! Prende 6 segnali dati in ingresso e, attraverso l'utilizzo di moltiplicatori e sottrattori, oltre 
--! all'opportuno troncamento dei valori intermedi calcolati, restituisce i parametri di uscita m ed q, rispettivamente coefficiente
--! angolare e intercetta della retta di regressione. La rappresentazione dei segnali è in signed fixed point. Lo schema a blocchi
--! dell'interfaccia del componente è riportata di seguito.
--! @htmlonly
--! <div align='center'>
--! <img src="../schemes/LinearRegressionBlackBox.png"/>
--! </div>
--! @endhtmlonly
--! <h3>Ingressi:</h3>
--! <h3>Uscite:</h3>
entity LinearRegression is
    Port (	clk 	: in std_logic;							--! segnale di clock, fornisce il segnale di temporizzazione ai componenti interni
    		load	: in std_logic;							--! segnale di load, agisce solo sui registri di bufferizzazione dei segnali dati in ingresso; si veda la documentazione dell'architettura implementativa		
    		reset_n : in std_logic;							--! segnale di reset asincrono (active-low) per i registri interni
    		prim	: in STD_LOGIC_VECTOR (5 downto 0);		--! costante in input, 6 bit di parte intera e 0 decimale (m.n = 5.0)
			Sum2	: in STD_LOGIC_VECTOR (23 downto 0);	--! segnale in input, 3 bit di parte intera e 21 decimale (m.n = 2.21)
			B		: in STD_LOGIC_VECTOR (23 downto 0);	--! segnale in input, msb di peso -1 (m.n = -1.24)
			Sum1	: in STD_LOGIC_VECTOR (23 downto 0);	--! segnale in input, 9 bit di parte intera e 15 decimale (m.n = 8.15)
			C		: in STD_LOGIC_VECTOR (23 downto 0);	--! segnale in input, msb di peso -7  (m.n = -7.30)
			A		: in STD_LOGIC_VECTOR (23 downto 0);	--! segnale in input, 6 bit di parte intera e 18 decimale (m.n = 5.18)
			m		: out STD_LOGIC_VECTOR (23 downto 0);	--! segnale in output, 11 bit di parte intera e 13 decimale (m.n = 10.13)
			q		: out STD_LOGIC_VECTOR (23 downto 0));	--! segnaes in output, 3 bit di parte intera e 21 decimale (m.n = 2.21)
end LinearRegression;


--! Per il calcolo dei parametri della regressione vengono utilizzati opportunamente dei moltiplicatori
--! e addizionatori/sottrattori. Per effettuare i calcoli in fixed point vengono adoperati opportuni troncamenti/
--! espansioni dei segnali. 
--! Il componente ha un'architettura pipelined, così come mostrato nello schema di seguito, nel quale sono indicati,
--! usando la notazione standard, le rappresentazioni binarie dei segnali dato in signed fixed-point. Si noti che
--! il segnale "load" agisce solo sul primo dei registri della pipe.
--! @htmlonly
--! <div align='center'>
--! <img src="../schemes/LinearRegression.png"/>
--! </div>
--! @endhtmlonly
architecture Structural of LinearRegression is

	component GenericBuffer is
		Generic (	width 		:		natural := 8;
					edge		:		std_logic := '1');
		Port (		clock 		: in	std_logic;
					reset_n 	: in	std_logic;
					load 		: in	std_logic;
					data_in 	: in	std_logic_vector(width-1 downto 0);
					data_out	: out	std_logic_vector(width-1 downto 0));
	end component;

	component multiplier is
		Generic (	nbits1		: natural := 8; 	
					nbits2		: natural := 8); 
		Port (		factor1 	: in STD_LOGIC_VECTOR (nbits1-1 downto 0);	
					factor2		: in STD_LOGIC_VECTOR (nbits2-1 downto 0);	
					prod 		: out STD_LOGIC_VECTOR (nbits1+nbits2-1 downto 0));	
	end component;

	component subtractor is
		generic (	nbits 		: 		natural := 32);
		port (		sub1 		: in	std_logic_vector(nbits-1 downto 0);		
					sub2 		: in	std_logic_vector(nbits-1 downto 0);		
					diff		: out	std_logic_vector(nbits-1 downto 0));
	end component;
	
----------------------------------------------------------------------------------------------------------------------------
-- Segnali di uscita del pipe-stage 0, si faccia riferimento allo schema architetturale
	signal prim_buff0	: std_logic_vector (5 downto 0) := (others => '0');		--! segnale prim bufferizzato, uscita del pipe-stage 0
	signal sum2_buff0	: std_logic_vector (23 downto 0) := (others => '0');	--! segnale sum2 bufferizzato, uscita del pipe-stage 0
	signal b_buff0		: std_logic_vector (23 downto 0) := (others => '0');	--! segnale b bufferizzato, uscita del pipe-stage 0
	signal sum1_buff0	: std_logic_vector (23 downto 0) := (others => '0');	--! segnale sum1 bufferizzato, uscita del pipe-stage 0
	signal c_buff0		: std_logic_vector (23 downto 0) := (others => '0');	--! segnale c bufferizzato, uscita del pipe-stage 0
	signal a_buff0		: std_logic_vector (23 downto 0) := (others => '0');	--! segnale a bufferizzato, uscita del pipe-stage 0
	
-----------------------------------------------------------------------------------------------------------------------------
-- Segnali di uscita di MULT1, MULT2, MULT3 e MULT4
	--! Uscita di MULT1 espressa su 48 bit, di cui 9 per la parte intera e 39 per quella decimale (m.n = 8.39).
	signal mult1_out : std_logic_vector (47 downto 0) := (others => '0'); 
	--! Uscita di MULT2 espressa su 48 bit, di cui 3 per la parte intera e 45 per quella decimale (m.n = 2.45).
	signal mult2_out : std_logic_vector (47 downto 0) := (others => '0'); 
	--! Uscita di MULT3 espressa su 30 bit, di cui 9 per la parte intera e 21 per quella decimale (m.n = 8.21).
	signal mult3_out : std_logic_vector (29 downto 0) := (others => '0'); 
	--! Uscita di MULT4 espressa su 48 bit, di cui 3 per la parte intera e 45 per quella decimale (m.n = 2.45).
	signal mult4_out : std_logic_vector (47 downto 0) := (others => '0'); 

----------------------------------------------------------------------------------------------------------------------------
-- Segnali di uscita del pipe-stage 1, si faccia riferimento allo schema architetturale
	--! L'uscita di MULT1 deve essere espressa su 24 bit, di cui 8 bit per la parte intera e 16 per quella decimale ( m.n = 7.16 ). 
	signal P1_buff1 : std_logic_vector (23 downto 0) := (others => '0'); 
	--!L'uscita di MULT2 deve essere espressa su 24 bit, di cui 1 per la parte intera e 23 per quella decimale (m.n = 0.23).
	signal P2_buff1 : std_logic_vector (23 downto 0) := (others => '0'); 
	--! L'uscita di MULT3 deve essere espressa su 24 bit di cui 8 sono per la parte intera, e 16 per quella decimale (m.n = 7.16).				
	signal P3_buff1 : std_logic_vector (23 downto 0) := (others => '0');
	--! L'uscita di MULT4 deve essere espressa su 24 bit, di cui 1 per la parte intera e 23 per quella decimale ( m.n = 0.23 ).
	signal P4_buff1 : std_logic_vector (23 downto 0) := (others => '0'); 
	--! segnale A bufferizzato, uscita del pipe-stage 1
	signal A_buff1	: std_logic_vector (23 downto 0) := (others => '0'); 
	
-----------------------------------------------------------------------------------------------------------------------------
-- Segnali di uscita di SUB5 e SUB6
	--! L'uscita di SUB5 deve essere espressa su 24 bit, di cui 8 per la parte intera  e 16 per quella decimale ( m.n = 7.16 ).
	signal S5 : std_logic_vector (23 downto 0) := (others => '0'); 
	--! L'uscita di SUB6 deve essere espressa su 24 bit, di cui 1 per la parte intera e 23 per quella decimale ( m.n = 0.23 ).
	signal S6 : std_logic_vector (23 downto 0) := (others => '0'); 

----------------------------------------------------------------------------------------------------------------------------
-- Segnali di uscita del pipe-stage 2, si faccia riferimento allo schema architetturale
	signal S5_buff2 : std_logic_vector (23 downto 0) := (others => '0');
	signal S6_buff2 : std_logic_vector (23 downto 0) := (others => '0');
	--! segnale A bufferizzato, uscita del pipe-stage 2
	signal A_buff2	: std_logic_vector (23 downto 0) := (others => '0'); 

-----------------------------------------------------------------------------------------------------------------------------
-- Segnali di uscita di MULTM e MULTQ
    --! Uscita di MULTM espressa su 48 bit, di cui 14 per la parte intera e 34 per quella decimale (m.n = 13.34).
	signal multM_out : std_logic_vector (47 downto 0) := (others => '0'); 
	--! Uscita di MULTQ espressa su 48 bit, di cui 7 per la parte intera e 41 per quella decimale (m.n = 6.41).
	signal multQ_out : std_logic_vector (47 downto 0) := (others => '0'); 

begin

----------------------------------------------------------------------------------------------------------------------------------
-- Istanze pipe-stage 0
----------------------------------------------------------------------------------------------------------------------------------

	pipestage0_buff_prim : GenericBuffer
		Generic map (	width 		=> 6,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> load,
						data_in 	=> prim,
						data_out	=> prim_buff0);

	pipestage0_buff_A : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> load,
						data_in 	=> A,
						data_out	=> A_buff0);
						
	pipestage0_buff_B : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> load,
						data_in 	=> B,
						data_out	=> B_buff0);
	
	pipestage0_buff_C : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> load,
						data_in 	=> C,
						data_out	=> C_buff0);
	
	pipestage0_buff_Sum1 : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> load,
						data_in 	=> Sum1,
						data_out	=> Sum1_buff0);
						
	pipestage0_buff_Sum2 : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> load,
						data_in 	=> Sum2,
						data_out	=> Sum2_buff0);

----------------------------------------------------------------------------------------------------------------------------------
-- Instanze MULT1, MULT2, MULT3 e MULT4
----------------------------------------------------------------------------------------------------------------------------------

	MULT3: multiplier
		Generic map( nbits1 => 6,
					 nbits2 => 24)
		port map ( factor1 => prim_buff0,
				   factor2 => Sum2_buff0,
				   prod => mult3_out);
				   
	MULT2: multiplier
		Generic map( nbits1 => 24,
					 nbits2 => 24)
		port map ( factor1 => Sum2_buff0,
				   factor2 => B_buff0,
				   prod => mult2_out);
				   
	MULT1: multiplier
		Generic map( nbits1 => 24,
					 nbits2 => 24)
		port map ( factor1 => B_buff0,
				   factor2 => Sum1_buff0,
				   prod => mult1_out);

	MULT4: multiplier
		Generic map( nbits1 => 24,
					 nbits2 => 24)
		port map ( factor1 => Sum1_buff0,
				   factor2 => C_buff0,
				   prod => mult4_out);

----------------------------------------------------------------------------------------------------------------------------------
-- Istanze pipe-stage 1
----------------------------------------------------------------------------------------------------------------------------------

	pipestage1_buff_A : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> '1',
						data_in 	=> A_buff0,
						data_out	=> A_buff1);

	pipestage1_buff_P1 : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> '1',
						data_in 	=> mult1_out(46 downto 23), -- Cambio di rappresentazione dell'uscita di MULT1 da 48 bit,
						data_out	=> P1_buff1);				-- di cui 9 per la parte intera (m.n = 8.39) a 24 bit, di cui 8
																-- per la parte intera (m.n = 7.16). Quindi tronchiamo 1 bit in
																-- testa e 23 in coda.
	pipestage1_buff_P2 : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> '1',
						data_in 	=> mult2_out(45 downto 22),	-- Cambio di rappresentazione dell'uscita di MULT2 da 48 bit, di 
						data_out	=> P2_buff1);				-- cui 3 per la parte intera (m.n = 2.45) a 24 bit, di cui 1 pe
																-- la parte intera (m.n = 0.23). Quindi tronchiamo 2 bit in testa e
																-- 22 in coda.
	pipestage1_buff_P3 : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> '1',
						data_in 	=> mult3_out(28 downto 5),	-- Cambio di rappresentazione dell'uscita di MULT3 da 30 bit, di cui
						data_out	=> P3_buff1);				--  9 per la parte intera (m.n = 8.21) a 24 bit, di cui 8 per la parte
																-- intera (m.n = 7.16). Quindi tronchiamo 1 bit in testa e 5 in coda.
	pipestage1_buff_P4 : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> '1',
						data_in 	=> mult4_out(45 downto 22),	-- Cambio di rappresentazione dell'uscita di MULT4 da 48 bit, di cui 3
						data_out	=> P4_buff1);				-- per la parte intera (m.n = 2.45) a 24 bit, di cui 1 per la parte
																-- intera (m.n = 0.23). Quindi tronchiamo 2 bit in testa e 22 in coda.

----------------------------------------------------------------------------------------------------------------------------------
-- Instanze SUB5 e SUB6
----------------------------------------------------------------------------------------------------------------------------------

	SUB5: subtractor
		Generic map (nbits => 24)
		port map( sub1 => P3_buff1,
				  sub2 => P1_buff1,
				  diff => S5);
		
	SUB6: subtractor
		Generic map (nbits => 24)
		port map( sub1 => P4_buff1,
				  sub2 => P2_buff1,
				  diff => S6);
				  
----------------------------------------------------------------------------------------------------------------------------------
-- Istanze pipe-stage 2
----------------------------------------------------------------------------------------------------------------------------------

	pipestage2_buff_A : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> load,
						data_in 	=> A_buff1,
						data_out	=> A_buff2);
						
	pipestage2_buff_S5 : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> '1',
						data_in 	=> S5,
						data_out	=> S5_buff2);
						
	pipestage2_buff_S6 : GenericBuffer
		Generic map (	width 		=> 24,
						edge		=> '1')
		Port map (		clock 		=> clk,
						reset_n 	=> reset_n,
						load 		=> '1',
						data_in 	=> S6,
						data_out	=> S6_buff2);

----------------------------------------------------------------------------------------------------------------------------------
-- Instanze MULTM e MULTQ
----------------------------------------------------------------------------------------------------------------------------------
				 
	MULTM: multiplier
		Generic map( nbits1 => 24,
					 nbits2 => 24)
		port map ( factor1 => S5_buff2,
				   factor2 => A_buff2,
				   prod => multM_out);
				   
	m <= multM_out (44 downto 21); -- L'uscita di  MULTM deve essere portata da una rappresentazione di 48 bit con
	-- 14 bit di parte intera e 34 decimale (m.n = 13.34), ad una di 24 bit con 11 bit di parte intera e 13 decimale (m.n = 10.13). 
	-- Quindi tronca 3 bit in testa e 21 in coda.		
				   
	MULTQ: multiplier
		Generic map( nbits1 => 24,
					 nbits2 => 24)
		port map ( factor1 => A_buff2,
				   factor2 => S6_buff2,
				   prod => multQ_out);	  			  
				   				  
	q <= multQ_out(43 downto 20);	-- L'uscita di  MULTQ deve essere portata da una rappresentazione di 48 bit con
	-- 7 bit di parte intera e 41 decimale (m.n = 6.41), ad una di 24 bit con 3 bit di parte intera e 21 decimale (m.n = 2.21). 
	-- Qindi tronca 4 bit in testa e 20 in coda.

end Structural;

--! @} 
