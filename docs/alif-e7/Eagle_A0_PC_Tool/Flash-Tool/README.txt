README: Eagle DevKit PC Tool binaries

  
Targeted Board: Eagle A0 DevKit 


Flash XiP Address: 

Flash XiP Address Mapped from 0xC000_00000   

  

This folder contains Binaries for Load binary in OSPI Flash, Boot the OSPI Flash Content and x86 GUI Tool to interact with Target for choose content to write into the flash. 

GUI_Tool : 

  + In Linux PC, download all the files from this folder and keep it in your local folder 

   

PC_Tool: 

  + B1C_PC_Tool_Burner.bin: Burner binary to interact with Linux PC and the content which want to flash. 

        Executable Address Space: ITCM 


  + set_OSPI_Boot_E8_HE.bin: Initialize the OSPI in XiP mode and execute the content from the flash memory.   

        Executable Address Space: ITCM