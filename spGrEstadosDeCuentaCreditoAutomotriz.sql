
 --EXEC spGrEstadosDeCuentaCreditoAutomotriz 352
ALTER  procedure [dbo].[spGrEstadosDeCuentaCreditoAutomotriz]  @idConsecutivoEDCCA int as           
          
--Declare  @idConsecutivoEDCCA int     
--set @idConsecutivoEDCCA = 155  
          
--Variables para generar archivo          
declare @OLEResult INT          
declare @FechaArch varchar(13)          
declare @idEncabezado int          
declare @idReferencia int          
DECLARE @contadorEstadoCuenta INT,  
  @contadorProcesoEstadoCuenta INT,  
  @contadorDetalle INT,  
  @contadorProcesoDetalle INT  
            
DECLARE @Archivo_EstadosDeCuenta VARCHAR(100),      
        @idConsecutivoDetalle INT,  
  @Registro VARCHAR(MAX),  
  @NombreArchivoEstadosDeCuenta NVARCHAR(MAX)  
  
  
/*Variables para el archivo*/  
DECLARE @idContrato VARCHAR(MAX),          
        @IdCliente VARCHAR(MAX),  
        @Contrato VARCHAR(MAX),  
        @Cliente VARCHAR(MAX),  
        @DireccionCliente VARCHAR(MAX),  
        @rfcCliente VARCHAR(MAX),  
        @FechaEmisonLetra VARCHAR(MAX),  
        @Periodo VARCHAR(MAX),  
        @DiasPeriodo VARCHAR(MAX),  
        @FechaCorte VARCHAR(MAX),  
        @TasaInteresOrdinario VARCHAR(MAX),  
        @Plazo VARCHAR(MAX),  
        @TasaInteresMoratorio VARCHAR(MAX),  
        @Moneda VARCHAR(MAX),  
        @CAT VARCHAR(MAX),  
        @DiaPago VARCHAR(MAX),  
        @MontoCredito VARCHAR(MAX),  
        @MensualidadesVencidas VARCHAR(MAX),  
        @CapitalMensualidadesVencidas VARCHAR(MAX),  
        @InteresOrdinarioMensualidadesVencidas VARCHAR(MAX),  
        @InteresMoraMensualidadesVencidas VARCHAR(MAX),  
        @IvaMensualidadesVencidas VARCHAR(MAX),  
        @TotalMensualidadesVencidas VARCHAR(MAX),  
        @FechaProximoPago VARCHAR(MAX),  
        @NumeroProximoPago VARCHAR(MAX),  
        @TotalProximoPago VARCHAR(MAX), /*Duda monto pagar capital*/  
        @MontoPagoCapital VARCHAR(MAX),  
        @MontoPagoIntereses VARCHAR(MAX),  
        @MontoPagoIVAIntereses VARCHAR(MAX),  
        @SaldoInicial VARCHAR(MAX),  
        @TotalCargos VARCHAR(MAX),      /*cargos periodo*/  
        @TotalAbonos VARCHAR(MAX),      /*abonos periodo*/  
        @SaldoFinal VARCHAR(MAX),  
        @SaldoFavor VARCHAR(MAX),  
        @ComisionApertura VARCHAR(MAX),  
        @Nota1 VARCHAR(MAX),  
        @Nota2 VARCHAR(MAX),  
        @Nota3 VARCHAR(MAX),  
		@correoCliente VARCHAR(40),  
		
		@fechaMovimiento VARCHAR(MAX),  
		@Concepto VARCHAR(MAX),  
		@Cargo VARCHAR(MAX),  
		@Abono VARCHAR(MAX),

		@RegimenFiscEmisor VARCHAR(50),
		@RazonSocialEmisor VARCHAR(500),
		@RegimenFiscReceptor VARCHAR(50),
		@CpReceptor VARCHAR(50),
		@FechaComisionApertura VARCHAR(60)
                  
  
 IF (OBJECT_ID('tempdb..#TemporalEncabezado')IS NOT NULL)   
 DROP TABLE #TemporalEncabezado  
 IF (OBJECT_ID('tempdb..#TemporalDetalle')IS NOT NULL)   
 DROP TABLE #TemporalDetalle  
   
-- Asignamos la fecha del archivo de texto          
set @FechaArch =right('00'+cast(DATEPART(dd,GETDATE()) as varchar),2) +           
    right('00'+cast(DATEPART(m,GETDATE()) as varchar),2) +          
                cast(DATEPART(YY,GETDATE()) as varchar)+ '-' +          
                right(cast(DATEPART(HOUR,GETDATE()) as varchar),2) +          
                right('00'+cast(DATEPART(MINUTE,GETDATE()) as varchar),2)     
                    
--While exists (SELECT 1 FROM  SRVDEV1.SIAC_Diario.dbo.CabeceraEdoCtaCA c inner join SRVDEV1.SIAC_Diario.dbo.DetalleEdoCtaCA d on d.idEncabezado = c.idEncabezado   
--      WHERE c.ConsecutivoEDCCA = @idConsecutivoEDCCA and c.idReferencia is null)        
--begin    
            
   declare @FS_Arch INT          
   declare @FileID_cab int          
    
   exec SRVDEV1.SIAC_Diario.dbo.spMnTraeFolio 'idReferencia', @idReferencia output    
   --SET @idReferencia = 155  
   SET @NombreArchivoEstadosDeCuenta =  'EstadosDeCuenta_' + right('0000000000' + cast(@idReferencia as varchar),10) + '-' + @FechaArch + '.txt'          
   set @Archivo_EstadosDeCuenta = CONCAT('\\srvcorpfact\SALIDA2\Temporal\Prueba_CA\' ,@NombreArchivoEstadosDeCuenta)       
  
   /* Creamos los Archivos de Texto */          
      -- Creamos el archivo cabecera          
      EXECUTE @OLEResult = master..xp_fileexist @Archivo_EstadosDeCuenta, @FS_Arch OUT          
      IF @FS_Arch > 0 EXECUTE ('EXEC master..xp_CMDShell "Del '+@Archivo_EstadosDeCuenta+'"')          
      EXECUTE @OLEResult = sp_OACreate 'Scripting.FileSystemObject', @FS_Arch OUT          
      -- Abrimos el archivo cabecera          
      EXECUTE @OLEResult = sp_OAMethod @FS_Arch, 'OpenTextFile', @FileID_cab OUT, @Archivo_EstadosDeCuenta, 8, 1          
  
  
        
   /**************************************************************LINEA LOTE ***********************************************************************************************/  
    /*------------Indica el inicio del archivo de integración y es requerido para su procesamiento. Sólo existe una sola línea en el archivo de texto plano-----------------*/  
    /************************************************************************************************************************************************************************/  
   --SET @REGISTRO = 'Lote|Emisor|UNIFIN|adolfo.alvarez@unifin.com.mx,oochoa@unifin.com.mx'    
  
   SET @REGISTRO = 'Lote|7.0|REPORTE_PROCESAMIENTO|UNIFIN|fzarate@unifin.com.mx';    
   EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
     
    
  
          
 --CVV Verificar que se inserte el registro de detalle para los contratos que no tienen movimientos en el mes         
       SELECT  ROW_NUMBER() OVER (ORDER BY CA.idContrato ASC) Orden,   
        CA.idContrato,  
        CA.idEncabezado,  
        Cl.IdCliente,  
        CA.Contrato,  
        CA.Correo,  
        CA.Cliente,  
        CA.DireccionCliente,  
        CA.rfcCliente,  
        CA.FechaEmisonLetra,  
        CA.Periodo,  
        CA.DiasPeriodo,  
        CA.FechaCorte,  
        CA.TasaInteresOrdinario,  
        CA.Plazo,  
        CA.TasaInteresMoratorio,  
        CA.Moneda,  
        CA.CAT,  
        CA.DiaPago,  
        CA.MontoCredito,  
        CA.MensualidadesVencidas,  
        CA.CapitalMensualidadesVencidas,  
        CA.InteresOrdinarioMensualidadesVencidas,  
        CA.InteresMoraMensualidadesVencidas,  
        CA.IvaMensualidadesVencidas,  
        CA.TotalMensualidadesVencidas,  
        CA.FechaProximoPago,  
        CA.NumeroProximoPago,  
        CA.TotalProximoPago, /*Duda monto pagar capital*/  
        CA.MontoPagoCapital,  
        CA.MontoPagoIntereses,  
        CA.MontoPagoIVAIntereses,  
        CA.SaldoInicial,  
        CA.TotalCargos,      /*cargos periodo*/  
        CA.TotalAbonos,      /*abonos periodo*/  
        CA.SaldoFinal,  
        CA.SaldoFavor,  
        CA.ComisionApertura,  
        CA.Nota1,  
        CA.Nota2,  
        CA.Nota3,
		CA.RegimenFiscEmisor,
		CA.RazonSocialEmisor,
		CA.RegimenFiscReceptor,
		CA.CpReceptor,
		FechaComisionapertura
    --CASE REPLACE(CA.NumeroProximoPago, ('/' + REPLACE(Plazo, ' meses', '')), '')  
    --    WHEN '12' THEN ISNULL(pol.AplicaRenovacion11, '0')  
    --    WHEN '24' THEN ISNULL(pol.AplicaRenovacion23, '0')  
    --    WHEN '36' THEN ISNULL(pol.AplicaRenovacion35, '0')  
    --    WHEN '42' THEN ISNULL(pol.AplicaRenovacion47, '0')  
    --    ELSE '0'  
    --END,  
    --CASE  
    --    WHEN CA.ComisionApertura > 0 THEN fca.FechaComAper  
    --    ELSE ''  
    --END  
    INTO #TemporalEncabezado  
    FROM SRVDEV1.SIAC_Diario.dbo.CabeceraEdoCtaCA CA  
     INNER JOIN SRVDEV1.SIAC_Diario.dbo.mnContrato CO  
      ON CO.IdContrato = CA.idContrato  
     INNER JOIN SRVDEV1.SIAC_Diario.dbo.ctCliente Cl  
      ON Cl.IdCliente = CO.IdCliente  
     LEFT JOIN  
     (  
      SELECT IdContrato,  
          CAST(AplicaRenovacion11 AS VARCHAR) AplicaRenovacion11,  
          CAST(AplicaRenovacion23 AS VARCHAR) AplicaRenovacion23,  
          CAST(AplicaRenovacion35 AS VARCHAR) AplicaRenovacion35,  
          CAST(AplicaRenovacion47 AS VARCHAR) AplicaRenovacion47  
      FROM SRVDEV1.SIAC_Diario.dbo.gsAdministracionRenovacionPolizaCA  
      GROUP BY IdContrato,  
         AplicaRenovacion11,  
         AplicaRenovacion23,  
         AplicaRenovacion35,  
         AplicaRenovacion47  
     ) pol  
      ON CA.idContrato = pol.IdContrato  
    LEFT JOIN  
    (  
        SELECT IdContrato,  
               MAX(CONVERT(VARCHAR(10), CrAbFechaValor, 103)) FechaComAper  
        FROM SRVDEV1.SIAC_Diario.dbo.mnCargoAbono  
        WHERE IdMovimiento = 51  
              AND CrAbReversado = 0  
              AND IdVencimiento IS NOT NULL  
        GROUP BY IdContrato
                 

    ) fca  
        ON CA.idContrato = fca.IdContrato  
    WHERE  CA.ConsecutivoEDCCA = @idConsecutivoEDCCA AND CA.idReferencia IS NULL  
    ORDER BY CA.idContrato;  
   
  
  
  
    SELECT ROW_NUMBER() OVER (PARTITION BY D.idEncabezado ORDER BY D.idEncabezado DESC, D.fechaMovimiento ASC) Orden,  
       D.idEncabezado,  
       D.fechaMovimiento,  
       D.Movimiento Concepto,  
       D.Cargo,  
       D.Abono  
   INTO #TemporalDetalle   
   FROM #TemporalEncabezado T  
    INNER JOIN SRVDEV1.SIAC_Diario.dbo.DetalleEdoCtaCA D  
     ON D.idEncabezado = T.idEncabezado  
   ORDER BY D.idEncabezado DESC,  
      D.fechaMovimiento ASC;  
 SELECT * FROM #TemporalEncabezado  
 SELECT * FROM #TemporalDetalle  
   
 SELECT @contadorEstadoCuenta = MAX(Orden), @contadorProcesoEstadoCuenta = 1 FROM #TemporalEncabezado  
   
 WHILE (@contadorProcesoEstadoCuenta <= @contadorEstadoCuenta)  
 BEGIN  
      SELECT @idContrato = idContrato,  
         @idEncabezado = idEncabezado,  
         @IdCliente = IdCliente,  
         @Contrato = Contrato,  
         @Cliente = Cliente,  
         @DireccionCliente = DireccionCliente,  
         @rfcCliente = rfcCliente,  
         @FechaEmisonLetra = FechaEmisonLetra,  
         @Periodo = Periodo,  
         @DiasPeriodo = DiasPeriodo,  
         @FechaCorte = FechaCorte,  
         @TasaInteresOrdinario = TasaInteresOrdinario,  
         @Plazo = Plazo,  
         @TasaInteresMoratorio = TasaInteresMoratorio,  
         @Moneda = Moneda,  
         @CAT = CAT,  
         @DiaPago = DiaPago,  
         @MontoCredito = MontoCredito,  
         @MensualidadesVencidas = MensualidadesVencidas,  
         @CapitalMensualidadesVencidas = CapitalMensualidadesVencidas,  
         @InteresOrdinarioMensualidadesVencidas = InteresOrdinarioMensualidadesVencidas,  
         @InteresMoraMensualidadesVencidas = InteresMoraMensualidadesVencidas,  
         @IvaMensualidadesVencidas = IvaMensualidadesVencidas,  
         @TotalMensualidadesVencidas = TotalMensualidadesVencidas,          
         @FechaProximoPago = FechaProximoPago,  
         @NumeroProximoPago = NumeroProximoPago,  
         @TotalProximoPago = TotalProximoPago, /*Duda monto pagar capital*/  
         @MontoPagoCapital = MontoPagoCapital,  
         @MontoPagoIntereses = MontoPagoIntereses,  
         @MontoPagoIVAIntereses = MontoPagoIVAIntereses,  
         @SaldoInicial = SaldoInicial,  
         @TotalCargos = TotalCargos,           /*cargos periodo*/  
         @TotalAbonos = TotalAbonos,           /*abonos periodo*/  
         @SaldoFinal = SaldoFinal,  
         @SaldoFavor = SaldoFavor,  
         @ComisionApertura = ComisionApertura,  
         @Nota1 = Nota1,  
         @Nota2 = Nota2,  
         @Nota3 = Nota3,  
         @correoCliente = Correo, 
		 @RegimenFiscEmisor = RegimenFiscEmisor,
		 @RazonSocialEmisor = RazonSocialEmisor,
		 @RegimenFiscReceptor = RegimenFiscReceptor,
		 @CpReceptor = CpReceptor,
		@FechaComisionApertura = FechaComisionapertura
     FROM #TemporalEncabezado  
     WHERE Orden = @contadorProcesoEstadoCuenta;  
 /*Escribir archivo*/  
 SET @Registro = ''  
	--SET @Registro = CONCAT('DOCUMENTO|NO_FISCAL|SI|SI|ESTADO DE CUENTA|ID_CONTROL|',@idReferencia, '|ENVIO_RECEPTOR|',@Cliente,'|facturase@unifin.com.mx|DATOSDECONTROL|DatoDeControl|fileName|',@idContrato,'_',@idEncabezado)  PROD
	SET @Registro = CONCAT('DOCUMENTO|NO_FISCAL|SI|SI|CREDIT AUTO|ID_CONTROL|',@idReferencia, '|ENVIO_RECEPTOR|',@Cliente,'|facturase@unifin.com.mx|DATOSDECONTROL|DatoDeControl|fileName|',@idContrato,'_',@idEncabezado)  --DES
          
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
      
       
  SET @Registro = ''  
  SET @Registro =concat('COMPROBANTE|4.0||',@idEncabezado,'|', CONVERT(VARCHAR(19), GETDATE(), 126) ,'|03||Contado|0||MXN|1|0|I|01|PUE|11560|')  
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
    
  SET @Registro = ''  
  SET @Registro ='EMISOR|UCR091026H12|'+@RazonSocialEmisor+'|'+ @RegimenFiscEmisor --hacer variable el rfc por empresa  
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
    
  SET @Registro = ''  
  SET @Registro =CONCAT('RECEPTOR|',@rfcCliente,'|',@Cliente,'|'+@CpReceptor+'|||'+@RegimenFiscReceptor+'|P01')  
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
    
  SET @Registro = ''  
  SET @Registro ='CONCEPTO|84101603||1|E48|UNI|0 |0|0||02'--|C_IMP_TRASLADADOS|IMP_TRASLADADO|0|002|Exento||||'  
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
    
  SET @Registro = ''  
  SET @Registro ='DOMICILIOS|DOMICILIO|CLIENTE|PRESIDENTE MASARYK|111|5|POLANCO V SECCIÓN|MIGUEL HIDALGO|CIUDAD DE MEXICO|MEXICO|11560|DOMICILIO|EMISOR|PRESIDENTE MASARYK|111| 5|POLANCO V SECCIÓN|MIGUEL HIDALGO|CIUDAD DE MEXICO|MEXICO|11560'  
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
    
  SET @Registro = ''  
  SET @Registro ='Impresion|Tabla|EstadoCuenta'  
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
      
  SET @Registro = ''  
  SET @Registro =CONCAT('Fila|Encabezado|Atributo|Contrato|',@Contrato,'|Atributo|Cliente|',@Cliente,'|Atributo|Direccion|',@DireccionCliente,'|Atributo|RFC|',@rfcCliente,'|Atributo|FechaEmision|',@FechaEmisonLetra,'|Atributo|Periodo|',@Periodo,'|Atributo|DiasPeriodo|',@DiasPeriodo,'|Atributo|FechaCorte|',@FechaCorte,'|Atributo|Bandera|1')  
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
    
  SET @Registro = ''  
  SET @Registro =CONCAT('Fila|InformacionCredito|Atributo|TasaInteresOrdinaria|',@TasaInteresOrdinario,'|Atributo|Plazo|',@Plazo,'|Atributo|TasaInteresMoratorio|',@TasaInteresMoratorio,'|Atributo|Moneda|',@Moneda,'|Atributo|CAT|',@CAT,'|Atributo|FechaPago|',@DiaPago,'|Atributo|MontoCredito|',@MontoCredito)  
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
    
  SET @Registro = ''  
  SET @Registro =CONCAT('Fila|MensualidadesVencidas|Atributo|NoMensualidadesVencidas|',@MensualidadesVencidas,'|Atributo|Capital|',@CapitalMensualidadesVencidas,'|Atributo|InteresesOrdinarios|',@InteresOrdinarioMensualidadesVencidas,'|Atributo|InteresesMoratorios|',@InteresMoraMensualidadesVencidas,'|Atributo|IVA|',@IvaMensualidadesVencidas,'|Atributo|TotalPagoVencido|',@TotalMensualidadesVencidas,'|Atributo|ProximoVencimiento|',@FechaProximoPago,'|Atributo|MensualidadNo|',@NumeroProximoPago,'|Atributo|MontoPagar|',@TotalProximoPago,'|Atributo|MontoPagarCapital|',@MontoPagoCapital,'|Atributo|MontoPagarInteresesOrdinarios|',@MontoPagoIntereses,'|Atributo|IVASobreIntereses|',@MontoPagoIVAIntereses)  
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
  
  SET @Registro = ''  
  SET @Registro =CONCAT('Fila|ResumenMovimientos|Atributo|SaldoInicial|',@SaldoInicial,'|Atributo|CargosPeriodo|',@TotalCargos,'|Atributo|AbonosPeriodo|',@TotalAbonos,'|Atributo|SaldoFinal|',@SaldoFinal,'|Atributo|PagoPendienteAplicar|',@SaldoFavor,'|Atributo|ComisionApertura|',@ComisionApertura,'|Atributo|Fecha|',@FechaComisionApertura)  
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
    
  SET @Registro = ''  
  SET @Registro ='Tabla|Detalle'  
  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
  
  SET @Registro = ''  
  SET @Registro ='Fila|Notas|Atributo|Nota1||Atributo|Nota2||Atributo|Nota3||Atributo|Pie|UNIFIN FINANCIERA S.A.P.I. DE C. V.  SOFOM E.N.R. - PRESIDENTE MASARYK 111- 5, COL. POLANCO V SECCIÓN, DISTRITO FEDERAL C.P. 11560 TEL 01 800 211 9000 / 5980 1513'  

  EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
    
  SELECT @contadorDetalle= MAX(Orden), @contadorProcesoDetalle = 1 FROM #TemporalDetalle WHERE idEncabezado = @idEncabezado  
    
  WHILE (@contadorProcesoDetalle <= @contadorDetalle)  
  BEGIN  
    
   SELECT @fechaMovimiento = fechaMovimiento,  
     @Concepto = Concepto,  
     @Cargo = Cargo,   
     @Abono = Abono  
   FROM #TemporalDetalle  
   WHERE idEncabezado = @idEncabezado  
   AND Orden = @contadorProcesoDetalle;  
   SET @Registro = ''  
   SET @Registro = CONCAT('Fila|Movimientos|Atributo|Fecha|',@fechaMovimiento,'|Atributo|Concepto|',@Concepto,'|Atributo|Cargos|',@Cargo,'|Atributo|Abonos|',@Abono)  
   EXECUTE @OLEResult = sp_OAMethod @FileID_cab, 'WriteLine', NULL, @REGISTRO;   
  
    
  
   SET @contadorProcesoDetalle = @contadorProcesoDetalle + 1  
  END  
  
  
 SET @contadorProcesoEstadoCuenta = @contadorProcesoEstadoCuenta +1  
  
  
  
 END  
  
   UPDATE Cab SET Cab.idReferencia = @idReferencia  
  FROM #TemporalEncabezado E  
   INNER JOIN SRVDEV1.SIAC_Diario.dbo.CabeceraEdoCtaCA Cab  
    ON Cab.idContrato = E.idContrato  
       AND Cab.ConsecutivoEDCCA = @idConsecutivoEDCCA;  
       
  
   EXECUTE @OLEResult = sp_OADestroy @FileID_cab          
  
   EXECUTE @OLEResult = sp_OADestroy @FS_Arch   
     /*
     INSERT INTO FACTELEC.dbo.grHistoricoFacturacionElectronicaRech  
  ( NombreArchivo, FechaTransaccion,StatusProcesado, TipoArchivo, FechaHoraCopiaArchivos )  
  VALUES (   @NombreArchivoEstadosDeCuenta, GETDATE(), 1, 'EDO', GETDATE() )  
  INSERT INTO dbo.ArchivosEstadosDeCuenta  
  (  
   idContrato,  
   idEncabezado,  
   nombreArchivo,  
   cntrNumero  
  )  
  SELECT E.idContrato,  
   E.idEncabezado,  
   CONCAT(E.idContrato,'_',E.idEncabezado),  
   E.Contrato  
  FROM #TemporalEncabezado E  
  WHERE NOT EXISTS  
  (  
   SELECT 1  
   FROM dbo.ArchivosEstadosDeCuenta A  
   WHERE A.idContrato = E.idContrato  
          AND A.idEncabezado = E.idEncabezado  
  );  
    
  EXECUTE ('EXEC master..xp_CMDShell "move '+@Archivo_EstadosDeCuenta+' D:\Reachcore\Salida\"');    
     EXECUTE ('EXEC master..xp_CMDShell " C:\BAT\Post-doc.BAT"');      
  EXECUTE ('EXEC master..xp_CMDShell "move  D:\Reachcore\Salida\'+@NombreArchivoEstadosDeCuenta+' D:\Reachcore\Salida\BKP"');      
  IF (OBJECT_ID('tempdb..#TemporalEncabezado')IS NOT NULL)   
   DROP TABLE #TemporalEncabezado  
  IF (OBJECT_ID('tempdb..#TemporalDetalle')IS NOT NULL)   
   DROP TABLE #TemporalDetalle         
  */
--end   
  
  
