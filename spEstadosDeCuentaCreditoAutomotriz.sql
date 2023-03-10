

--/**********************************************/
-- Modificó: RMG  27-09-2017 Se agrego que no tomara en cuenta en el encabezado contratos con estado en Siniestro 
---                          ya que no genera detalle debido a que no hay vencimientos.
---  25-07-2022 MASD - se realiza la validacion de clientes que deben de aparecer el calculo del IVA
--                   - se quita suma del saldo vendico al saldo final del periodo
--                   - se modifica el calculo de las mensualidades que tiene el contrato de acuerdo a la tabla de amortización
--/**********************************************/

ALTER PROCEDURE [dbo].[spEstadosDeCuentaCreditoAutomotriz] @Consecutivo INT OUTPUT AS            
            
SET LANGUAGE español            
--------Parametros del sp            
            
DECLARE @fechaInicio DATETIME,            
        @fechaFin DATETIME
		--@Consecutivo int                      
                  
--set @fechaInicio = '16-09-2022'  --16-10-2022  si quiero el de octubre tengo que poner septiembre por que se resta un mes en fecha inicio
set @fechaInicio = '01-11-2022'  --01-12-2022            
--SELECT @fechaInicio = DATEADD(MM,-1,dbo.fdtFechaSinHora(GETDATE())) --16-09-2022         
              
IF DATEPART(dd,@fechaInicio) = 1               
BEGIN            
 --La fecha de corte es fin de mes            
 SET @fechaFin = DATEADD(MM,1,@fechaInicio) - 1             
END            
ELSE --Si es mitad de mes            
BEGIN            
 SET @fechaFin = DATEADD(MM,1,('15-' + CAST(DATEPART(mm,@fechaInicio)AS VARCHAR) + '-' +  CAST(DATEPART(yy,@fechaInicio)AS VARCHAR)))            
END            
            
--Varibles para encabezado             
DECLARE             
 @Prepagos INT = 0,            
 @error BIT,                 
 @Contrato VARCHAR(11),              
 @Cliente VARCHAR(300),              
 @Correo VARCHAR(100),              
 @Direccion VARCHAR(350),              
 @RFC VARCHAR(15),              
 @FechaEmision VARCHAR(35),            
 @Periodo VARCHAR(100),              
 @DiasPeriodo INTEGER,              
 @TasaOrdinaria VARCHAR(10),              
 @TasaMoratorios VARCHAR(10),            
 @CAT VARCHAR(10),            -- AAR Se crea variable incluir el CAT, 24/02/2015 18:34:20
 @Plazo VARCHAR(10),              
 @Moneda VARCHAR(10),              
 @DiaPago VARCHAR(30),              
 @MensualidadesVencidas INT = 0,            
 @CapitalMoroso DECIMAL (18,2) = 0.00,              
 @InteresOrdMora DECIMAL (18,2) = 0.00,              
 @InteresMoraAlCorte DECIMAL (18,2) = 0.00,              
 @ComisionCobranza DECIMAL (18,2) = 0.00,              
 @IVAMoroso DECIMAL (18,2) = 0.00,              
 @TotalPagoVencido DECIMAL (18,2) = 0.00,              
 @ProximoPago VARCHAR(35) = '',              
 @NoPago VARCHAR (7) = '',              
 @TotalProximoPago DECIMAL (18,2) = 0.00,              
 @SaldoInicial DECIMAL (18,2) = 0.00,              
 @SaldoFinal DECIMAL (18,2) = 0.00,              
 @CargosPeriodo DECIMAL (18,2) = 0.00,              
 @AbonosPeriodo DECIMAL (18,2) = 0.00,              
 @SaldoFavor DECIMAL (18,2) = 0.00,            
 @Notas1 VARCHAR(600) = '',            
 @Notas2 VARCHAR(600) = '',            
 @Notas3 VARCHAR(600) = '',            
 @RFC_E VARCHAR(13) = '',            
 @NOMBRE_E VARCHAR(100) = '',            
 @DATOS_E VARCHAR(200) = '',    
 @idEmpresa TINYINT, --Se agrego cambios 20/03/2020
 @interesesSaldoInsoluto DECIMAL (18,2) = 0.00,
 @SaldoInsoluto DECIMAL (18,2) = 0.00,
  --Campos Agregados 17/06/2015 Ticket 34510
 @ComisionApertura DECIMAL (18,2) = 0.00,
 @MontoCredito DECIMAL (18,2) = 0.00,
 @PagoCapital DECIMAL (18,2) = 0.00,
 @PagoIntereses DECIMAL (18,2) = 0.00,
 @PagoIVAIntereses DECIMAL (18,2) = 0.00,
 @FechaCorte  VARCHAR(35),
 
 @SaldoInicialProximoPeriodo DECIMAL(18,2) = 0.00,   
 @SaldoFinalProximoPeriodo DECIMAL(18,2) = 0.00,

 @cntrFechaTerminacion VARCHAR(60),
 @FechaComisionApertura VARCHAR(60),

 @RegimenFiscEmisor VARCHAR(50),
 @RazonSocialEmisor VARCHAR(500),
 @RegimenFiscReceptor VARCHAR(50),
 @CpReceptor VARCHAR(50)                      
             
--Varibles para el detalle            
DECLARE             
 @idconsecutivo INT,            
 @fechaMovimiento DATETIME,            
 @Concepto VARCHAR(150),            
 @Cargo DECIMAL (18,2),            
 @Abono DECIMAL (18,2)            
            
            
--Declare @Consecutivo int            
DECLARE @FolioEncabezado INT            
                                                                     
EXEC dbo.spMnTraeFolio 'ConsecutivoEDCCA',@Consecutivo OUTPUT                                             
                  
            
--Variables de uso general            
DECLARE @iva DECIMAL(3,2),            
 @idContrato INT,            
 @Registro_cab VARCHAR(8000),              
 @Registro_det VARCHAR(5000)            
 --AGREGADO MASD PARA APLICACION DE IVA ACIERTOS CLIENTES 25072022
 ,@AplicaIVA INT
                                            
            
--Obtiene IVA            
  
SELECT @iva=CONVERT(DECIMAL,PrSsValor)/100 
  FROM ctParametroSistema 
 WHERE IdSistema = 0 AND IdParametroSistema = 4              
            
--Crea una tabla temporal para los cargos pendientes de cada contrato            
/*MG
create table #Cargos(            
idContrato int,            
IdCargoAbono int,            
idMovimiento int,            
idMovimientoOrigen int,            
capital decimal (12,4),            
interes decimal (12,4),            
ivas decimal (12,4),    
mora decimal (12,4),            
ivaMora decimal (12,4)            
) */

DECLARE @Cargos TABLE(            
idContrato   INT,            
IdCargoAbono INT,            
idMovimiento INT,            
idMovimientoOrigen INT,            
capital DECIMAL (12,4),            
interes DECIMAL (12,4),            
ivas    DECIMAL (12,4),            
mora    DECIMAL (12,4),            
ivaMora DECIMAL (12,4)            
)              
  

--IF OBJECT_ID('tempdb.dbo.#tablaTemporal', 'U') IS NOT NULL
--	DROP TABLE #tablaTemporal; 
----Tabla temporal-- hasta el 1 de abril
--select IdContrato, IdCliente, CntrNumero, 16 as diaGenerado
--into #tablaTemporal
--from mnContrato where CntrNumero in (
--'CA17269-01'
--,'CA17416-01'
--,'CA171947-01'
--,'CA172080-01'
--,'CA18499-01'
--,'CA181040-01'
--,'CA181365-02'
--,'CA192509-01'
--,'CA20006-01'
--,'CA20828-01'
--)
--union all
--select IdContrato, IdCliente, CntrNumero, 1 as diaGenerado 
--from mnContrato where CntrNumero in (
--'CA17541-01'
--,'CA171598-01'
--,'CA171911-01'
--,'CA18701-01'
--,'CA18915-01'
--,'CA181016-01'
--,'CA191007-01'
--,'CA192539-01'
--,'CA201053-02'
--,'CA21112-01'
--)
   
--OBTIENE TODOS LOS DATOS FISCALES DE LOS CLIENTES PARA LA NUEVA PLANTILLA
IF OBJECT_ID('tempdb.dbo.#UNI2PROD_DIR', 'U') IS NOT NULL
	DROP TABLE #UNI2PROD_DIR;

SELECT accounts_dire_direccion_1accounts_ida, cp, id_c, regimen_fiscal_sat_c, tipodepersona_c, denominacion_c, rfc_c, nombre, inactivo
INTO #UNI2PROD_DIR
FROM OPENQUERY ([UNI2PRODUCCION],'select b.accounts_dire_direccion_1accounts_ida, b.cp, c.id_c, c.regimen_fiscal_sat_c, c.tipodepersona_c, c.denominacion_c, c.rfc_c,a.name nombre, b.inactivo 
									FROM unifin.accounts_cstm c 
									JOIN unifin.accounts a on c.id_c=a.id
									LEFT JOIN	(
												SELECT cp.name cp, rel.accounts_dire_direccion_1accounts_ida, dir.inactivo
												FROM unifin.dire_direccion dir
												inner join unifin.accounts_dire_direccion_1_c rel ON rel.accounts_dire_direccion_1dire_direccion_idb = dir.id
												Inner Join unifin.dire_direccion_dire_codigopostal_c dircp on dircp.dire_direccion_dire_codigopostaldire_direccion_idb = dir.id and dircp.deleted = dir.deleted
												Inner Join unifin.dire_codigopostal cp on cp.id = dircp.dire_direccion_dire_codigopostaldire_codigopostal_ida and cp.deleted = dir.deleted and dir.inactivo=0 AND indicador&2=2
											) b on b.accounts_dire_direccion_1accounts_ida = c.id_c
');


 --Obtiene todos los contratos que necesitan emisión de estado de cuenta      
 DECLARE crsEncabezado
 
 CURSOR FOR            
 
 SELECT DISTINCT cto.idcontrato             
 FROM mncontrato cto 
 INNER JOIN ctEstadoContrato ec 
         ON ec.IdIndicadorEstado = cto.IdIndicadorEstado            
 INNER JOIN mnTablaAmortizacion ta 
         ON ta.IdContrato = cto.IdContrato 
		AND ta.IdConsecutivoTabla = 1            
        AND TbAmFechaExigibilidad BETWEEN DATEADD(dd,1,@fechaInicio) AND @fechaFin            
 WHERE cntrIdProductoFinanciero IN (22,30)            
   AND ec.InCnActivo = 1     
   AND cto.idindicadorestado NOT IN (11,13)       
   AND CAST(CAST(DAY(cto.CntrFechaPrimerPago) AS VARCHAR) + '/' + CAST(MONTH(@fechaFin) AS VARCHAR) + '/' + CAST(YEAR(@fechaFin) AS VARCHAR) AS DATETIME)            
 BETWEEN DATEADD(DD,1,@fechaInicio) AND @fechaFin  
 AND cto.IdContrato --= 127122    
	--in (127389,127390,126702,127009,59979) --16/09/2022
	in (127016,127122,127171,127321) --01-10-2022
 OPEN crsEncabezado              
 FETCH NEXT FROM crsEncabezado INTO  @idContrato              
 WHILE @@FETCH_STATUS = 0              
 BEGIN  --Comienza el cursor para los encabezados            
             
 --Obtiene el folio para identificar cada encabezado            
 EXEC dbo.spMnTraeFolio 'idEncabezadoEC',@FolioEncabezado OUTPUT             
               
 --Limpia la tabla            
 --truncate table @Cargos            
   DELETE FROM @cargos
            
 --Obtiene la cantidad de prepagos realizados hasta la fecha de corte            
 SELECT @Prepagos = ISNULL((SELECT COUNT(tbamnumeropago)             
   FROM mnTablaAmortizacion t             
  WHERE TbAmFechaExigibilidad <= @fechaFin             
    AND ISNULL(TbAmIdConsecutivoPrepago,0) > 0             
    AND IdContrato = @idContrato             
    AND t.IdConsecutivoTabla = 1),0)            
            
 --*--Obtiene la información del encabezado--*--            
 SELECT 
		 @Contrato = cto.CntrNumero,            
		 @Cliente = dbo.fsObtenNombreCliente(cto.IdCliente),             
		 @Correo = ISNULL(cmn.CmncDescripcion,'agayosso@unifin.com.mx'),            
		 @Direccion = dbo.fsObtenDireccionCLiente(cto.IdCliente,1),             
		 @RFC = ClntRfc,            
		 @FechaEmision = LOWER(dbo.fvSCConvierteFechaLetra(CONVERT(VARCHAR(10),DATEADD(d,1,@fechafin),103),1)),            
		 @Periodo = LOWER(dbo.fvSCConvierteFechaLetra(CONVERT(VARCHAR(10),@fechaInicio,103),1)) + ' al ' + LOWER(dbo.fvSCConvierteFechaLetra(CONVERT(VARCHAR(10),@fechafin,103),1)),            
		 @DiasPeriodo = DATEDIFF(DD, @fechaInicio, DATEADD(DD,1,@fechaFin)),          
		 ----Información del credito----              
		 @TasaOrdinaria = CONVERT(VARCHAR(6),(CONVERT(DECIMAL(8,2), CntrTasa)))+'%',            
		 @TasaMoratorios = CONVERT(VARCHAR(6),(CONVERT(DECIMAL(8,2), cntrmoratasafija)))+'%',            
		 @CAT = CONVERT(VARCHAR(6),(CONVERT(DECIMAL(8,1), cto.cntrCAT)))+'%',                 -- AAR Se crea variable incluir el CAT, 24/02/2015 18:34:20
		 --@Plazo = convert(varchar(3),CntrNumeroPagos+1)+ ' meses',  
		 @Plazo = CONVERT(VARCHAR(3),(SELECT MAX(TbAmNumeroPago) FROM mntablaamortizacion tam WHERE tam.idconsecutivotabla=1 AND tam.idcontrato=cto.idcontrato))+ ' meses',
		 @Moneda = LOWER(m.MndaDescripcion),            
		 @DiaPago = 'Día '+ CONVERT(VARCHAR(2),DATEPART(dd,CntrFechaPrimerPago))+' de cada mes',            
		 -----Proxima mensualidad----            
		 @ProximoPago = ISNULL(LOWER(dbo.fvSCConvierteFechaLetra(CONVERT(VARCHAR(10),ProxPago.TbAmFechaExigibilidad,103),1)),''),             
		 --@NoPago = isnull(convert(varchar(3),(ProxPago.TbAmNumeroPago - @Prepagos)) + '/' + convert(varchar(3), (cntrnumeropagos + 1)),''),  
		 @NoPago = ISNULL(CONVERT(VARCHAR(3),(ProxPago.TbAmNumeroPago - @Prepagos)) + '/' + CONVERT(VARCHAR(3), (SELECT MAX(TbAmNumeroPago) FROM mntablaamortizacion tam WHERE tam.idconsecutivotabla=1 AND tam.idcontrato=cto.idcontrato)),''), 
		 @TotalProximoPago = ISNULL(ProxPago.Total,0), 
		 --SE AGREGAN CAMPOS TICKET 34510 OOA 17/06/2015
		 @ComisionApertura = ISNULL((SELECT ISNULL(ta.TbAmAmortizacion,0) + ISNULL(ta.TbAmIvaCapital,0)
									   FROM mnContrato c 
								 INNER JOIN mnEncabezadoTabla et 
										 ON et.IdContrato =  c.IdContrato
								 INNER JOIN mnTablaAmortizacion ta 
										 ON ta.IdContrato = c.IdContrato 
										AND ta.IdConsecutivoTabla = et.IdConsecutivoTabla
										AND et.IdMovimiento = 51  
										AND c.IdContrato = @idContrato 
										AND ta.TbAmFechaExigibilidad BETWEEN @fechaInicio AND @fechaFin),0),
		@FechaComisionApertura = (SELECT ISNULL(LOWER(dbo.fvSCConvierteFechaLetra(CONVERT(VARCHAR(10), ta.TbAmFechaExigibilidad, 103),1)),'')
									   FROM mnContrato c 
								 INNER JOIN mnEncabezadoTabla et 
										 ON et.IdContrato =  c.IdContrato
								 INNER JOIN mnTablaAmortizacion ta 
										 ON ta.IdContrato = c.IdContrato 
										AND ta.IdConsecutivoTabla = et.IdConsecutivoTabla
										AND et.IdMovimiento = 51  
										AND c.IdContrato = @idContrato ),
										--AND ta.TbAmFechaExigibilidad BETWEEN @fechaInicio AND @fechaFin),

		 @MontoCredito = ISNULL(cto.CntrMontoFinanciar,0)  ,
		 @PagoCapital = ISNULL(ProxPago.PagoCapital,0),    
		 @PagoIntereses =ISNULL(ProxPago.PagoIntereses,0),
		 @PagoIVAIntereses =ISNULL(ProxPago.PagoIVAIntereses,0),
		 @FechaCorte = ISNULL(LOWER(dbo.fvSCConvierteFechaLetra(CONVERT(VARCHAR(10),ProxPago.TbAmFechaExigibilidad,103),1)),''),
		 @SaldoFinalProximoPeriodo = ISNULL(ProxPago.SaldoFinalProxPeriodo,0)
		  ,@idEmpresa = cto.IdEmpresa
		 ,@AplicaIVa =CASE WHEN cto.IdEmpresa=2 AND c.IdRegimenFiscal IN (2,3) THEN 0 ELSE 1 END ---Agrgado MASD
		 ,@RegimenFiscReceptor = (SELECT top 1 regimen_fiscal_sat_c FROM #UNI2PROD_DIR where rfc_c COLLATE Modern_Spanish_CI_AS = c.ClntRfc ) --'601' --PENDIENTE BUSCAR VALOR en CRM
		 ,@CpReceptor = (SELECT top 1 cp FROM #UNI2PROD_DIR where rfc_c COLLATE Modern_Spanish_CI_AS = c.ClntRfc ) --'57200' -- PENDIENTE BUSCAR VALOR en CRM
			
			
FROM mnContrato cto 
INNER JOIN ctCliente c 
		ON cto.IdCliente=c.IdCliente             
INNER JOIN mnProductoFinanciero pf 
		ON cto.cntrIdProductoFinanciero=pf.IdProductoFinanciero            
INNER JOIN ctMoneda m 
		ON m.IdMoneda = pf.IdMoneda            
LEFT OUTER JOIN (SELECT TOP 1 idcontrato, 
		                TbAmNumeroPago, 
						TbAmFechaExigibilidad, 
						SUM(TbAmTotal) Total, 
						SUM(TbAmAmortizacion) PagoCapital,
				        SUM(TbAmInteres) PagoIntereses, 
						SUM(TbAmIvaInteres) PagoIVAIntereses,
						SUM(TbAmSaldoFinal) SaldoFinalProxPeriodo            
                    FROM mntablaamortizacion 
				WHERE IdContrato = @idContrato 
					AND TbAmFechaExigibilidad >= @fechaFin            
                GROUP BY idcontrato,TbAmNumeroPago, TbAmFechaExigibilidad      
                ORDER BY 2) AS ProxPago
		ON ProxPago.IdContrato=CTO.IdContrato            
LEFT JOIN ctComunicacion cmn 
		ON cmn.IdCliente=c.IdCliente 
		AND IdTipoComunicacion=5              
    WHERE  cto.IdContrato = @idContrato     
            
 --Insert los cargos pendientes en la tabla temporal            
 INSERT INTO @Cargos 
            
 SELECT  
		 ca.idcontrato, ca.IdCargoAbono, CA.idmovimiento, ca.CrAbIdMovimientoOrigen origen,            
		 ca.crabCapital Capital,            
		 ca.crabInteres Interes,            
		 (ca.CrAbIvaCapital + Ca.CrAbIvaInteres) ivas,             
		 ISNULL(dbo.fdMnCalculaMoratorio(m.MrtrFechaInicial,@fechaFin,ca.idcontrato,ISNULL(m.MrtrImporteBase,0)),0) moratorios,            
		 --isnull(dbo.fdMnCalculaMoratorio(m.MrtrFechaInicial,@fechaFin,ca.idcontrato,isnull(m.MrtrImporteBase,0)) * @iva,0) ivamoratorios            
		 ROUND(ISNULL(dbo.fdMnCalculaMoratorio(m.MrtrFechaInicial,@fechaFin,ca.idcontrato,ISNULL(m.MrtrImporteBase,0)) * @iva,0),2)*@AplicaIVA ivamoratorios            
 FROM mnCargoAbono ca             
 left outer join mnMoratorio m 
              on ca.IdCargoAbono = m.IdCargoAbono 
			 and m.MrtrTotalMoratorio > 0 
			 and MrtrIndicadorEstado = 'A'            
 left outer join mnCargoAbono mora 
              on m.MrtrIdCargoAbonoGenerado = mora.IdCargoAbono             
             and mora.IdMovimiento = 7 
			 and isnull(mora.CrAbPagado,'S') = 'N' --isnull para los que no tienen moratorios generados o fueron condonados            
 where ca.IdContrato = @idContrato            
 and ca.CrAbPagado = 'N'            
 and ca.IdMovimiento not in (7) --Todos menos moratorios ya calculados            
 and ca.CrAbFechaValor <= @fechaFin   
            
 union  --Moratorios que tiene pendientes generados por cargos ya pagados         
    
 select  cargo.idcontrato, 
         cargo.IdCargoAbono, 
		 mora.IdMovimiento, 
		 mora.CrAbIdMovimientoOrigen origen, 
		 0, 
		 0, 
		 0,            
         MrtrImporteMoratorio moratorios,            
         MrtrIvaMoratorio ivamoratorios            
 from mnCargoAbono cargo           
 inner join mnmoratorio m 
         on m.IdCargoAbono = cargo.IdCargoAbono 
		and m.MrtrTotalMoratorio > 0             
		and cargo.CrAbPagado = 'S'            
		and cargo.CrAbReversado = 0            
		and MrtrIndicadorEstado = 'A'             
 inner join mnCargoAbono mora 
         on m.MrtrIdCargoAbonoGenerado = mora.IdCargoAbono             
        and mora.CrAbPagado = 'N'             
        and mora.IdMovimiento = 7            
      where cargo.IdContrato = @idContrato            
        and cargo.CrAbFechaValor <= @fechaFin            
             
 ----Información de Mensualidades Vencidas   
            
  select @MensualidadesVencidas = isnull(max(MensualidadesVencidas) ,0)            
    from (select COUNT(idMovimientoOrigen) MensualidadesVencidas 
	        from @Cargos 
		   where idMovimientoOrigen in (14,15,16,17,51) 
		group by idMovimientoOrigen) v   
		           
  select @CapitalMoroso = isnull(SUM(capital),0),            
         @InteresOrdMora = isnull(SUM(interes),0)            
    from @Cargos 
   where idMovimientoOrigen in (14,15,16,17,51)  
                 
  select @InteresMoraAlCorte = isnull(SUM(mora),0) 
    from @Cargos 
   where idMovimientoOrigen in (7,14,15,16,17,51)  
                
  select @ComisionCobranza = isnull(SUM(capital),0) 
    from @Cargos 
   where idMovimientoOrigen in (8)     
             
  select @IVAMoroso = isnull(SUM(isnull(ivas,0) + ISNULL(ivamora,0))*@AplicaIVA,0) 
    from @Cargos 
   where idMovimientoOrigen in (7,8,14,15,16,17,51)  
             
  set @TotalPagoVencido = @CapitalMoroso + @InteresOrdMora + @InteresMoraAlCorte + @ComisionCobranza + @IVAMoroso            
              
  select @SaldoFavor = isnull(SUM(capital),0) 
    from @Cargos 
   where idMovimiento in (1)           
    
      
  --Reinicia el acumulado de cargos y abonos            
  set @CargosPeriodo = 0            
  set @AbonosPeriodo = 0            
               
  --Comienza el cursor para los detalles             
  declare crsDetalle cursor for            
     select 
		ROW_NUMBER() over (order by Fecha), 
		Fecha, 
		Concepto, 
		CARGO, 
		ABONO 
		from (select v.VncmFechaExigibilidad Fecha, 
		             1 orden,           
                     'Capital mensualidad '+ CONVERT(varchar(5), v.VncmNumeroPago - isnull((select COUNT(tbamnumeropago) 
					                                                                          from mnTablaAmortizacion t 
																							 where TbAmFechaExigibilidad < v.VncmFechaExigibilidad             
                                                                                               and isnull(TbAmIdConsecutivoPrepago,0) > 0 
																							   and IdContrato = @idContrato 
																							   and t.IdConsecutivoTabla = 1),0)) + '/' + convert(varchar(3),cto.cntrnumeroPagos + 1)  Concepto,              
                       sum(v.vncmCapital) CARGO,              
                       0 ABONO             
                  from mncontrato cto 
			inner join mnVencimiento v 
			        on v.IdContrato = cto.IdContrato 
				   and v.VnMensaje not in ('PREPAGO', 'PREPAGO TOTAL')            
            inner join mnEncabezadoTabla et 
			        on et.IdContrato = cto.IdContrato 
				   and et.IdMovimiento in (14,15,16,17) 
				   and et.IdConsecutivoTabla = v.IdConsecutivoTabla       
                 where cto.IdContrato = @idcontrato             
                   and v.VncmFechaExigibilidad between @fechaInicio and @fechaFin              
              group by cto.IdContrato, v.VncmFechaExigibilidad,            
                       v.VncmFechaExigibilidad, v.VncmNumeroPago, cntrnumeroPagos              
                having SUM(v.vncmCapital) > 0            
           
		   union   
		             
           select v.VncmFechaExigibilidad Fecha, 2 orden,            
                 'Interes ordinario mensualidad ' + CONVERT(varchar(5), v.VncmNumeroPago - isnull((select COUNT(tbamnumeropago) 
				                                                                                     from mnTablaAmortizacion t 
																									where TbAmFechaExigibilidad < v.VncmFechaExigibilidad             
																									   and isnull(TbAmIdConsecutivoPrepago,0) > 0 
																									   and IdContrato = @idContrato 
																									   and t.IdConsecutivoTabla = 1),0)) + '/' + convert(varchar(3),cto.cntrnumeroPagos + 1) Concepto,              
           sum(v.vncmInteres) CARGO,              
           0 ABONO             
           from mncontrato cto 
		   inner join mnVencimiento v 
		           on v.IdContrato = cto.IdContrato 
				  and v.VnMensaje not in ('PREPAGO', 'PREPAGO TOTAL')             
           inner join mnEncabezadoTabla et 
		           on et.IdContrato = cto.IdContrato 
				  and et.IdMovimiento in (14,15,16,17) 
				  and et.IdConsecutivoTabla = v.IdConsecutivoTabla            
           where cto.IdContrato = @idcontrato             
           and v.VncmFechaExigibilidad between @fechaInicio and @fechaFin   AND @AplicaIVA=1            
           group by cto.IdContrato, v.VncmFechaExigibilidad, v.VncmNumeroPago, v.VncmFechaExigibilidad, cntrnumeroPagos              
           having SUM(v.vncmInteres) > 0     
		          
           union            

           select v.VncmFechaExigibilidad Fecha,  
		          3 orden,            
                  'IVA mensualidad '+ CONVERT(varchar(5), v.VncmNumeroPago - isnull((select COUNT(tbamnumeropago) 
				                                                                       from mnTablaAmortizacion t 
																					  where TbAmFechaExigibilidad < v.VncmFechaExigibilidad             
                                                                                        and isnull(TbAmIdConsecutivoPrepago,0) > 0 
																						and IdContrato = @idContrato 
																						and t.IdConsecutivoTabla = 1),0)) + '/' + convert(varchar(3),cto.cntrnumeroPagos + 1) Concepto,              
					sum(v.VncmIvaCapital + v.VncmIvaInteres)*@AplicaIVA CARGO,              
					0 ABONO             
           from mncontrato cto 
		   inner join mnVencimiento v 
		           on v.IdContrato = cto.IdContrato 
				  and v.VnMensaje not in ('PREPAGO', 'PREPAGO TOTAL')             
           inner join mnEncabezadoTabla et 
		           on et.IdContrato = cto.IdContrato 
				  and et.IdMovimiento in (14,15,16,17) 
				  and et.IdConsecutivoTabla = v.IdConsecutivoTabla            
           where cto.IdContrato = @idcontrato             
           and v.VncmFechaExigibilidad between @fechaInicio and @fechaFin              
           group by cto.IdContrato, v.VncmFechaExigibilidad, v.VncmNumeroPago, v.VncmFechaExigibilidad, cntrnumeroPagos               
           having SUM(v.VncmIvaCapital + v.VncmIvaInteres) > 0            
     
	 Union   
	           
			select v.VncmFechaExigibilidad Fecha, 4 orden,    
				'Comisión por apertura' Concepto,              
				sum(v.vncmCapital) CARGO,              
				0 ABONO             
			from mncontrato cto 
	       inner join mnVencimiento v 
		           on v.IdContrato = cto.IdContrato            
           inner join mnEncabezadoTabla et 
		           on et.IdContrato = cto.IdContrato 
				  and et.IdMovimiento = 51 
				  and et.IdConsecutivoTabla = v.IdConsecutivoTabla            
           where cto.IdContrato = @idcontrato             
           and v.VncmFechaExigibilidad between @fechaInicio and @fechaFin   
           group by cto.IdContrato, v.VncmFechaExigibilidad            
           having SUM(v.vncmCapital) > 0   
		            
           union             
           
		   select v.VncmFechaExigibilidad Fecha, 
		          5 orden,            
                  'Interes ordinario comisión por apertura' Concepto,              
                  sum(v.vncmInteres) CARGO,              
                  0 ABONO             
           from mncontrato cto 
		   inner join mnVencimiento v 
		           on v.IdContrato = cto.IdContrato            
           inner join mnEncabezadoTabla et 
		           on et.IdContrato = cto.IdContrato 
				  and et.IdMovimiento = 51 
				  and et.IdConsecutivoTabla = v.IdConsecutivoTabla            
           where cto.IdContrato = @idcontrato             
           and v.VncmFechaExigibilidad between @fechaInicio and @fechaFin              
           group by cto.IdContrato, v.VncmFechaExigibilidad              
           having SUM(v.vncmInteres) > 0            
           
		   union            
           
		   select  v.VncmFechaExigibilidad Fecha,  
		           6 orden,            
                  'IVA comisión por apertura' Concepto,              
                   sum(v.vncmIvaCapital + v.vncmIvaInteres)*@AplicaIVA CARGO,              
                   0 ABONO             
           from mncontrato cto 
		   inner join mnVencimiento v 
		           on v.IdContrato = cto.IdContrato            
           inner join mnEncabezadoTabla et 
		           on et.IdContrato = cto.IdContrato 
				  and et.IdMovimiento = 51 
				  and et.IdConsecutivoTabla = v.IdConsecutivoTabla            
           where cto.IdContrato = @idcontrato             
             and v.VncmFechaExigibilidad between @fechaInicio and @fechaFin   AND @AplicaIVA=1           
           group by cto.IdContrato, v.VncmFechaExigibilidad               
           having SUM(v.vncmIvaCapital + v.vncmIvaInteres) > 0            
                       
     union            
     
	 select gc.GsCbFechaCreacion Fecha,  7 orden,            
			'Comisión por cobranza mensualidad ' + CONVERT(varchar(5), v.VncmNumeroPago - isnull((select COUNT(tbamnumeropago) 
			                                                                                        from mnTablaAmortizacion t 
																								   where TbAmFechaExigibilidad < v.VncmFechaExigibilidad             
	  	                                                                                             and isnull(TbAmIdConsecutivoPrepago,0) > 0 
																									 and IdContrato = @idContrato 
																									 and t.IdConsecutivoTabla = 1),0)) + '/' + convert(varchar(3),cto.cntrnumeroPagos + 1) Concepto,              
			gc.GsCbImporteGastoCobranza CARGO,              
			0 ABONO             
      from mncontrato cto 
	  inner join mnCargoAbono ca 
	          on cto.idcontrato = ca.IdContrato 
			 and ca.CrAbReversado = 0              
      inner join mnGastoCobranza gc 
	          on gc.IdCargoAbono = ca.IdCargoAbono            
      inner join mnVencimiento v 
	          on v.IdVencimiento = ca.IdVencimiento              
     where cto.IdContrato = @idcontrato 
	        and gc.GsCbFechaCreacion between @fechaInicio and @fechaFin            
                 
     union   
	          
     select gc.GsCbFechaCreacion Fecha,  8 orden,        
     'IVA comisión por cobranza mensualidad ' + CONVERT(varchar(5), v.VncmNumeroPago - isnull((select COUNT(tbamnumeropago) 
	                                                                                             from mnTablaAmortizacion t 
																							    where TbAmFechaExigibilidad < v.VncmFechaExigibilidad             
                                                                                                and isnull(TbAmIdConsecutivoPrepago,0) > 0 
																								  and IdContrato = @idContrato 
																								  and t.IdConsecutivoTabla = 1),0)) + '/' + convert(varchar(3),cto.cntrnumeroPagos + 1) Concepto,              
     gc.GsCbIvaGastoCobranza *@AplicaIVA CARGO,              
     0 ABONO             
     from mncontrato cto 
	 inner join mnCargoAbono ca 
	         on cto.idcontrato = ca.IdContrato 
			and ca.CrAbReversado = 0              
     inner join mnGastoCobranza gc 
	         on gc.IdCargoAbono = ca.IdCargoAbono            
     inner join mnVencimiento v 
	         on v.IdVencimiento = ca.IdVencimiento              
     where cto.IdContrato = @idcontrato 
	       and gc.GsCbFechaCreacion between @fechaInicio and @fechaFin  AND @AplicaIVA  =1        
                 
     union  --Falta revisar y modifcar la tarea diaria de generacion de moratorios            
     
	 select             
			case when m.MrtrFechaFinal >  @fechaFin then @fechaFin  -- Los moratios comienzan dentro del periodo pero no han sido cubiertos            
			when m.MrtrFechaFinal <= @fechaFin then m.MrtrFechaFinal end Fecha, 9 orden, --Los moratorios se generaron y cubrieron este periodo              
			case when ca.CrAbIdMovimientoOrigen = 51 then 'Interes moratorio comisión apertura '             
			when ca.CrAbIdMovimientoOrigen in (14,15,16,17) then 'Interes moratorio mensualidad '            
			else 'Interes moratorio ' end + isnull(CONVERT(varchar(5), v.VncmNumeroPago - isnull((select COUNT(tbamnumeropago) 
			                                                                                        from mnTablaAmortizacion t 
																								   where TbAmFechaExigibilidad < v.VncmFechaExigibilidad             
			                                                                                         and isnull(TbAmIdConsecutivoPrepago,0) > 0 
																									 and IdContrato = @idContrato 
																									 and t.IdConsecutivoTabla = 1),0)) + '/' + convert(varchar(3),cto.cntrnumeroPagos + 1),'') Concepto,              
			SUM(round(case when m.MrtrFechaFinal >= @fechaFin and m.MrtrFechaInicial >= @fechaInicio 
			                 then -- Los moratios comienzan dentro del periodo pero no han sido cubiertos dentro del mismo              
			                 dbo.fdMnCalculaMoratorio(m.mrtrFechainicial,@fechaFin,@idcontrato,m.MrtrImporteBase)               
			                 when m.MrtrFechaFinal <= @fechaFin and m.MrtrFechaInicial >= @fechaInicio 
							 then --Los moratorios comienzan este perodo y se pagaron este mismo periodo              
							MrtrImporteMoratorio              
							end ,2)) CARGO,              
			0 ABONO            
     from mncontrato cto 
	 inner join mnCargoAbono ca 
	         on cto.idcontrato = ca.IdContrato 
			and ca.CrAbReversado = 0               
     inner join mnMoratorio m 
	         on m.IdCargoAbono = ca.IdCargoAbono 
			and m.MrtrTotalMoratorio > 0             
     left outer join mnEncabezadoTabla et 
	         on et.IdContrato = cto.IdContrato 
			and et.IdMovimiento = ca.CrAbIdMovimientoOrigen --Se agrega et para no ligar el vencimiento cuando es CA            
     left outer join mnVencimiento v 
	         on v.IdVencimiento = ca.IdVencimiento 
			and v.IdConsecutivoTabla = et.IdConsecutivoTabla 
			and et.IdMovimiento not in (51)              
     where cto.IdContrato = @idcontrato and              
            m.MrtrFechaInicial between @fechaInicio and @fechaFin            
     GROUP BY CTO.IdContrato, MrtrFechaFinal, 
	          case when ca.CrAbIdMovimientoOrigen = 51 then 'Interes moratorio comisión apertura '             
                   when ca.CrAbIdMovimientoOrigen in (14,15,16,17) then 'Interes moratorio mensualidad '             
               else 'Interes moratorio ' 
			   end, v.VncmNumeroPago, v.VncmFechaExigibilidad, cto.cntrnumeroPagos      
     union  
	             
     select            
            case when m.MrtrFechaFinal >  @fechaFin 
			       then @fechaFin  -- Los moratios comienzan dentro del periodo pero no han sido cubiertos          
                 when m.MrtrFechaFinal <= @fechaFin 
				   then m.MrtrFechaFinal 
			end Fecha, 10 orden, --Los moratorios se generaron y cubrieron este periodo              
            case when ca.CrAbIdMovimientoOrigen = 51 
			       then 'IVA interes moratorio comisión apertura '            
                 when ca.CrAbIdMovimientoOrigen in (14,15,16,17) then 'IVA interes moratorio mensualidad '             
                 else 'IVA interes moratorio ' 
				 end + isnull(CONVERT(varchar(5), v.VncmNumeroPago - isnull((select COUNT(tbamnumeropago) 
				                                                               from mnTablaAmortizacion t 
																			  where TbAmFechaExigibilidad < v.VncmFechaExigibilidad             
                                                                                and isnull(TbAmIdConsecutivoPrepago,0) > 0 
																				and IdContrato = @idContrato 
																				and t.IdConsecutivoTabla = 1),0)) + '/' + convert(varchar(3),cto.cntrnumeroPagos + 1),'') Concepto,              
            SUM(round(case when m.MrtrFechaFinal >= @fechaFin and m.MrtrFechaInicial >= @fechaInicio 
			               then -- Los moratios comienzan dentro del periodo pero no han sido cubiertos dentro del mismo              
                               (dbo.fdMnCalculaMoratorio(m.mrtrFechainicial,@fechaFin,@idcontrato,m.MrtrImporteBase)) * @iva            
                           when m.MrtrFechaFinal <= @fechaFin and m.MrtrFechaInicial >= @fechaInicio 
						   then --Los moratorios comienzan este perodo y se pagaron este mismo periodo              
							  MrtrIvaMoratorio              
						   end ,2))*@AplicaIVA CARGO,              
                         0 ABONO            
     from mncontrato cto 
	 inner join mnCargoAbono ca 
	         on cto.idcontrato = ca.IdContrato 
			and ca.CrAbReversado = 0                
     inner join mnMoratorio m 
	         on m.IdCargoAbono = ca.IdCargoAbono 
			and m.MrtrTotalMoratorio > 0             
     left outer join mnEncabezadoTabla et 
	         on et.IdContrato = cto.IdContrato 
			and et.IdMovimiento = ca.CrAbIdMovimientoOrigen --Se agrega et para no ligar el vencimiento cuando es CA            
     left outer join mnVencimiento v 
	         on v.IdVencimiento = ca.IdVencimiento 
			and v.IdConsecutivoTabla = et.IdConsecutivoTabla 
			and et.IdMovimiento not in (51)              
          where cto.IdContrato = @idcontrato and              
                m.MrtrFechaInicial between @fechaInicio and @fechaFin    AND @AplicaIVA=1        
       GROUP BY CTO.IdContrato, MrtrFechaFinal, case when ca.CrAbIdMovimientoOrigen = 51 
	                                                 then 'IVA interes moratorio comisión apertura '             
                                                     when ca.CrAbIdMovimientoOrigen in (14,15,16,17) 
													 then 'IVA interes moratorio mensualidad '             
                                                 else 'IVA interes moratorio ' end,  
												   v.VncmNumeroPago, 
												   v.VncmFechaExigibilidad, 
												   cto.cntrnumeroPagos            
                
   --Resto de cargos            
     union  
	            
     select ca.CrAbFechaValor Fecha, 
	        11 orden,               
			LOWER(m.MvmnNombre) Concepto,            
			case m.MvmnCargoAbono when 'C' then ca.CrAbCapital else 0 end CARGO,              
			case m.MvmnCargoAbono when 'A' then ca.CrAbCapital else 0 end ABONO             
     from mncontrato cto 
	 inner join mnCargoAbono ca 
	         on cto.idcontrato = ca.IdContrato 
			and ca.IdMovimiento not in (1,2,3,7,8,9,10,12,14,15,16,17,26,51)             
            and ca.CrAbMarcaUsoPrepago = 0 
			and ca.CrAbReversado = 0              
     inner join mnMovimiento m 
	         on m.IdMovimiento = ca.IdMovimiento 
			and ca.IdProductoFinanciero = m.IdProductoFinanciero                
     where cto.IdContrato = @idcontrato             
and ca.CrAbFechaValor between @fechaInicio and @fechaFin            
     and ca.CrAbCapital > 0            
     
	 union             

     select ca.CrAbFechaValor Fecha,  12 orden,            
			'Interes ordinario ' + LOWER(m.MvmnNombre) Concepto,            
			case m.MvmnCargoAbono when 'C' then ca.CrAbInteres else 0 end CARGO,              
			case m.MvmnCargoAbono when 'A' then ca.CrAbInteres else 0 end ABONO             
     from mncontrato cto 
	 inner join mnCargoAbono ca 
	         on cto.idcontrato = ca.IdContrato 
			and ca.IdMovimiento not in (1,2,3,7,8,9,10,12,14,15,16,17,26,51)             
            and ca.CrAbMarcaUsoPrepago = 0 
			and ca.CrAbReversado = 0              
     inner join mnMovimiento m 
	         on m.IdMovimiento = ca.IdMovimiento 
			and ca.IdProductoFinanciero = m.IdProductoFinanciero                
     where cto.IdContrato = @idcontrato    
		and ca.CrAbFechaValor between @fechaInicio and @fechaFin            
		and ca.CrAbInteres > 0  
		           
     union
	              
     select ca.CrAbFechaValor Fecha, 13 orden,              
           'IVA ' + LOWER(m.MvmnNombre) Concepto,            
           case m.MvmnCargoAbono when 'C' then ca.CrAbIvaCapital + ca.CrAbIvaInteres else 0 end CARGO,          
           case m.MvmnCargoAbono when 'A' then ca.CrAbIvaCapital + ca.CrAbIvaInteres else 0 end ABONO     
     from mncontrato cto 
	 inner join mnCargoAbono ca 
	         on cto.idcontrato = ca.IdContrato 
			and ca.IdMovimiento not in (1,2,3,7,8,9,10,12,14,15,16,17,26,51)             
            and ca.CrAbMarcaUsoPrepago = 0 and ca.CrAbReversado = 0        
     inner join mnMovimiento m 
	         on m.IdMovimiento = ca.IdMovimiento 
			and ca.IdProductoFinanciero = m.IdProductoFinanciero            
     where cto.IdContrato = @idcontrato             
     and ca.CrAbFechaValor between @fechaInicio and @fechaFin   AND @AplicaIVA=1         
     and (ca.CrAbIvaCapital > 0 or ca.CrAbIvaInteres > 0)            
               
   union  
               
     select m.MrtrFechaCondonacion Fecha, 14 orden,             
			'Condonación intereses moratorios' Concepto,              
			0 CARGO,              
			sum(m.MrtrTotalMoratorio) ABONO              
     from mncontrato cto 
	 inner join mnCargoAbono ca 
	         on cto.idcontrato = ca.IdContrato 
			and ca.CrAbReversado = 0  --CVV             
     inner join mnMoratorio m 
	         on m.IdCargoAbono = ca.IdCargoAbono 
			and m.MrtrTotalMoratorio > 0 
			and MrtrFechaCondonacion is not null              
     left outer join mnVencimiento v 
	         on v.IdVencimiento = ca.IdVencimiento              
          where cto.IdContrato = @idcontrato             
            and m.MrtrFechaCondonacion between @fechaInicio and @fechaFin            
       group by cto.IdContrato, m.MrtrFechaCondonacion            
            
     union    
	          
     select ca.CrAbFechaValor Fecha, 15 orden,              
            'Cancelación ' + case when ca.CrAbIdMovimientoOrigen in (14,15,16,17) then 'mensualidad ' 
			                      else isnull(rtrim(replace(LOWER(m.MvmnNombre),'vencimiento ','')),LOWER(mto.MvmnDescripcion)) end             
    + ' ' + isnull(CONVERT(varchar(5), v.VncmNumeroPago - isnull((select COUNT(tbamnumeropago) 
	                                                                from mnTablaAmortizacion t 
																   where TbAmFechaExigibilidad < v.VncmFechaExigibilidad             
                                                                     and isnull(TbAmIdConsecutivoPrepago,0) > 0 
																	 and IdContrato = @idContrato 
																	 and t.IdConsecutivoTabla = 1),0)) + '/' + convert(varchar(3),cto.cntrnumeroPagos + 1),'')  Concepto,            
     0 CARGO,              
     sum(ca.CrAbTotal) ABONO             
     from mncontrato cto 
	 inner join mnCargoAbono ca 
	         on cto.idcontrato = ca.IdContrato 
			and ca.IdMovimiento = 3 
			and ca.CrAbReversado = 0  --CVV            
     inner join mnNotaCredito nc 
	         on nc.IdCargoAbono = ca.IdCargoAbono            
     inner join mnSerieDocumentoFiscal sdf 
	         on nc.IdSerieDocumentoFiscal = sdf.IdSerieDocumentoFiscal 
			and SrdfSerie = 'CF'            
     inner join mnMovimiento mto 
	         on mto.IdMovimiento = ca.CrAbIdMovimientoOrigen 
			and mto.IdProductoFinanciero = ca.IdProductoFinanciero            
     inner join mnCargoAbono co 
	         on co.IdVencimiento = ca.IdVencimiento 
		    and co.IdCargoAbono = nc.NtCrIdCargoAbonoOrigen             
     left outer join mnEncabezadoTabla et 
	         on et.IdContrato = cto.IdContrato 
			and et.IdMovimiento = ca.CrAbIdMovimientoOrigen  --Se agrega et para no ligar el vencimiento cuando es CA            
     left outer join mnVencimiento v 
	         on v.IdVencimiento = ca.IdVencimiento 
			and et.IdMovimiento not in (51) and v.IdConsecutivoTabla = et.IdConsecutivoTabla               
     left outer join mnMovimiento m 
	         on m.IdMovimiento = co.IdMovimiento 
			and co.IdProductoFinanciero = m.IdProductoFinanciero             
     where cto.IdContrato = @idcontrato             
     and ca.CrAbFechaValor between @fechaInicio and @fechaFin             
     group by ca.CrAbFechaValor,            
     'Cancelación ' + case when ca.CrAbIdMovimientoOrigen in (14,15,16,17) 
	                       then 'mensualidad ' 
					  else isnull(rtrim(replace(LOWER(m.MvmnNombre),'vencimiento ','')),LOWER(mto.MvmnDescripcion)) end,            
     v.VncmFechaExigibilidad, v.VncmNumeroPago, cto.CntrNumeroPagos            
               
            
     union       
	        
     select p.PagoFechaRealRecepcion Fecha, 16 orden,            
            'Pago aplicado' Concepto,              
            0 CARGO,              
            sum(ap.ApPgPagoTotal) ABONO     
     from mncontrato cto 
	 inner join mnCargoAbono ca 
	         on cto.idcontrato = ca.IdContrato 
			and CrAbPagado = 'S' 
			and CrAbReversado = 0 
			and ca.CrAbMarcaUsoPrepago = 0               
     inner join mnAplicacionPago ap 
	         on ap.IdCargoAbono = ca.IdCargoAbono              
     inner join mnPago p
	         on p.IdPago = ap.IdPago 
			and p.PagoTipo not in (1,3,5)            
     /*Se agrega mnvencimiento para el caso en que pagan los saldos pendientes del prepago con el  mismo pago que cubrieron la mensualidad             
    Ej. contrato 15070 periodo del 1 al 30 abril 2013 */            
     left outer join mnVencimiento v 
	         on v.IdVencimiento = ca.IdVencimiento            
     where cto.IdContrato = @idcontrato 
	   and p.PagoFechaRealRecepcion between @fechaInicio and @fechaFin            
       and ca.IdMovimiento not in (1,12)              
       and isnull(VnMensaje,'') not like '%prepago%'            
     group by p.PagoFechaRealRecepcion, cto.IdContrato            
                 
     union  
	             
     select p.PagoFechaRealRecepcion Fecha, 17 orden,             
           'Pago anticipado' Concepto,              
            0 CARGO,            
           sum(ca.crabTotal) ABONO            
     from mncontrato cto 
	 inner join mnCargoAbono ca 
	         on cto.idcontrato = ca.IdContrato 
			and ca.CrAbReversado = 0            
            and ca.IdMovimiento in (14,15,16,17) 
			and CrAbPagado = 'S' 
			and ca.CrAbMarcaUsoPrepago = 1            
     inner join mnCargoManual cm 
	         on cm.IdContrato = cto.IdContrato 
			and cm.IdCargoAbono = ca.IdCargoAbono 
			and CrMnDescripcion = 'PREPAGO'             
     inner join mnAplicacionPago ap 
	         on ap.IdCargoAbono = ca.IdCargoAbono              
     inner join mnPago p 
	         on p.IdPago = ap.IdPago            
     where cto.IdContrato = @idcontrato             
            and p.PagoFechaRealRecepcion between @fechaInicio and @fechaFin              
   group by p.PagoFechaRealRecepcion,cto.IdContrato                 
     ) det order by Fecha, orden            
     open crsDetalle              
  fetch next from crsDetalle into  @idconsecutivo, @fechaMovimiento, @Concepto, @Cargo, @Abono 
             
  While @@FETCH_STATUS = 0                
  
  Begin            
   --Inserta registros del detalle            
   insert into DetalleEdoCtaCA (idEncabezado, Consecutivo, fechaMovimiento, Movimiento, Cargo, Abono, FechaCreación)    
   values(@FolioEncabezado, @idconsecutivo, CONVERT(varchar(10),@fechaMovimiento, 103), @Concepto, @Cargo, @Abono, GETDATE())            
               
   --incrementa cargos y abonos del periodo            
   set @CargosPeriodo = @CargosPeriodo + @Cargo            
   set @AbonosPeriodo = @AbonosPeriodo + @Abono            
               
   Fetch Next From  crsDetalle into  @idconsecutivo, @fechaMovimiento, @Concepto, @Cargo, @Abono                              
  End --Termina cursor para detalle            
  Close crsDetalle              
  Deallocate crsDetalle             
             
  ----Resumen del mes            
            
  ---Calcula el saldo insoluto al inicio del periodo para el caso de que el contrato no tenga movimiento en el periodo        
  select @SaldoInicial = dbo.fdMnSaldoInsolutoEnFecha(@idcontrato,@fechaInicio)        
  
  
  ---Obtiene el saldo final del periodo anterior     
  select top 1 @SaldoInicial = isnull(SaldoFinal,dbo.fdMnSaldoInsolutoEnFecha(@idcontrato,@fechaInicio))            
  from CabeceraEdoCtaCA c             
  where idcontrato = @idcontrato            
  and FechaEmision = DATEADD(m,-1,DATEADD(d,1,@fechafin))            
  order by idEncabezado desc            
                
  --saldo insoluto a la fecha fin + cartera morosa              
  select @SaldoFinal =  dbo.fdMnSaldoInsolutoEnFecha(@idcontrato,@fechaFin) --+ @TotalPagoVencido  
  
   --sse obtiene el saldo inicial y final del próximo periodo
   
   set @SaldoInicialProximoPeriodo = @SaldoFinal
   set @SaldoFinalProximoPeriodo =  @SaldoFinalProximoPeriodo + @TotalPagoVencido  
                    
		--inicio se obtiene saldo insoluto
    set @SaldoInsoluto = dbo.fdMnSaldoInsolutoEnFecha(@idcontrato,@fechaFin)
  set @interesesSaldoInsoluto = ISNULL((select SUM(TbAmInteres) from mnTablaAmortizacion t 
											where TbAmFechaInicial >= @fechaFin and TbAmFechaFinal <= DATEADD(MONTH,1,@fechaFin)            
                                            and IdContrato = @idContrato ),0.0)				          
               
  --Nota de prepagos             
  -- info del ultimo prepago realizado en el periodo, el monto de la mensualidad debe ser igual al que se muestra en  monto a pagar del proximo pago (encabezado)            
              
  set @Notas2 = ''            
  if dbo.fdMnSaldoInsolutoEnFecha(@idContrato,@fechaFin) > 0
              
	  begin            
		   select @Notas2 = isnull(MAX(nota),'') 
			 from (            
					select top 1 p.PagoFechaRealRecepcion, 
						   isnull('Por su pago anticipado del día ' + convert(varchar(10),p.PagoFechaRealRecepcion,103) +             
								  ' sus mensualidades se reducen a $' + cast(convert(varchar,cast(SUM(e.entbrenta) as money),1) as varchar),'') nota            
						   from mnCargoAbono ca             
					 inner join mnAplicacionPago ap 
							 on ap.IdCargoAbono = ca.IdCargoAbono              
							and ca.CrAbReversado = 0 
							and ca.IdMovimiento in (14,15,16,17) 
							and CrAbPagado = 'S' 
							and ca.CrAbMarcaUsoPrepago = 1            
					 inner join mnPago p 
							 on p.IdPago = ap.IdPago            
					 inner join mnEncabezadoTabla e 
							 on e.IdContrato = ca.IdContrato 
							and e.IdMovimiento in (14,15,16,17)             
						  where ca.IdContrato = @idcontrato             
							and p.PagoFechaRealRecepcion between @fechaInicio and @fechaFin            
					   group by p.PagoFechaRealRecepcion order by 1 desc) t            
		 end             
                
  --Nota para devolución de saldos            
set @Notas1 = ''--'Devolución de saldo a favor el día 00/00/0000 por un importe de $0,000.00.'             
  
  select @Notas1 = COALESCE(@notas1 + '','') + isnull(saldo,'') 
  from            
	  (select ' el día ' +  convert(varchar(10),ca.CrAbFechaValor,103) + ' por un importe de $' + cast(convert(varchar,cast(SUM(CrAbTotal) as money),1) as varchar) + '.  ' saldo            
	     from mncontrato cto 
		inner join mnCargoAbono ca 
		        on cto.idcontrato = ca.IdContrato             
	           and ca.IdMovimiento = 12 
			   and ca.CrAbReversado = 0 
			   and ca.CrAbPagado = 'S'            
	    inner join mnMovimiento m 
		        on m.IdMovimiento = ca.IdMovimiento 
			   and ca.IdProductoFinanciero = m.IdProductoFinanciero                
	         where cto.IdContrato = @idcontrato             
	           and ca.CrAbFechaValor between @fechaInicio and @fechaFin            
	           and ca.CrAbCapital > 0            
	  group by CrAbFechaValor) t     
	         
  if @notas1 <> '' set @Notas1 = 'Devolución de saldo a favor: ' + @Notas1            
     
--if exists(select IdContrato, IdCliente from #tablaTemporal where IdContrato = @idcontrato and diaGenerado = Day(GETDATE()) )
--begin 
--	set @Notas1 = 'Como resultado de un análisis de desempeño del seguro de desempleo contratado por UNIFIN, se tomó la decisión de cancelar el mismo, y notamos que tu crédito no presentaba dicha cancelación, por lo que en tu próxima domiciliación estaremos aplicando una nota de crédito y cancelado futuros cargos por este concepto. En caso de presentar algún adeudo, este será aplicado al monto pendiente de pago.'
--end
----else
----begin
----	set @Notas1 = cast(@idcontrato as varchar(50)) + '' + cast(Day(GETDATE()) as varchar(50))
----end
         
  --Nota adicional            
		set @Notas3 = ''  
		
		----Obtiene la información de la empresa
		
		select @RFC_E = e.EmprRfc, 
		       @NOMBRE_E = e.EmprRazonSocial,
		       @DATOS_E = e.EmprRazonSocial + ' - ' + e.EmprCalle + ' ' + e.EmprNumeroExterior + '-' + e.EmprNumeroInterior + ', COL. ' + e.EmprColonia + ', ' + est.EstdNombre + ' C.P. ' + e.EmprCodigoPostal,
				@RegimenFiscEmisor = e.IdRegimenFiscalSAT -- RegimenFiscSAT,
				,@RazonSocialEmisor = e.EmprRazonSocial --RazonSocialSAT
		 from mnContrato cto 
		 inner join ctEmpresa e 
		         on e.IdEmpresa = cto.IdEmpresa 
		 inner join ctEstado est 
		         on est.IdEstado = e.IdEstado 
				and est.IdPais = e.IdPais
		WHERE e.EmprRfc = 'UCR091026H12' --cto.IdContrato = @idContrato                
                  
	--Inserta registro de encabezado            
	insert into CabeceraEdoCtaCA(
	            idEncabezado, 
				idContrato,
				Contrato, 
				Cliente, 
				Correo, 
				DireccionCliente, 
				rfcCliente,          
				FechaEmisonLetra, 
				FechaEmision,
				Periodo, 
				DiasPeriodo,
				TasaInteresOrdinario, 
				TasaInteresMoratorio,
				Plazo, 
				Moneda, 
				DiaPago,
				MensualidadesVencidas, 
				CapitalMensualidadesVencidas, 
				InteresOrdinarioMensualidadesVencidas, 
				InteresMoraMensualidadesVencidas,
				ComisionCobranza, 
				IvaMensualidadesVencidas, 
				TotalMensualidadesVencidas,            
				FechaProximoPago, 
				NumeroProximoPago, 
				TotalProximoPago,            
				SaldoInicial, 
				SaldoFinal, 
				TotalCargos, 
				TotalAbonos, 
				SaldoFavor,            
				Nota1, 
				Nota2, 
				Nota3,
				ComisionApertura,
				MontoCredito,
				MontoPagoCapital,
				MontoPagoIntereses,
				MontoPagoIVAIntereses,
				FechaCorte,
				rfcEmisor, 
				Emisor, 
				DatosEmisor, 
				FechaCreación, 
				ConsecutivoEDCCA,
				CAT,
				SaldoInicialProximoPeriodo,
				SaldoFinalProximoPeriodo,
				RegimenFiscEmisor,
				RazonSocialEmisor,
				RegimenFiscReceptor,
				CpReceptor)      
		Values(@FolioEncabezado, 
		        @idContrato, 
				@Contrato, 
				@Cliente, 
				@Correo, 
				@Direccion, 
				@RFC,            
				@FechaEmision, 
				DATEADD(d,1,@fechafin), 
				@Periodo, 
				@DiasPeriodo,         
				@TasaOrdinaria, 
				@TasaMoratorios, 
				@Plazo, 
				@Moneda, 
				@DiaPago,             
				@MensualidadesVencidas, 
				@CapitalMoroso, 
				@InteresOrdMora, 
				@InteresMoraAlCorte,            
				@ComisionCobranza, 
				@IVAMoroso, 
				@TotalPagoVencido,            
				@ProximoPago, 
				@NoPago, 
				@TotalProximoPago,            
				@SaldoInicial, 
				@SaldoFinal, 
				@CargosPeriodo, 
				@AbonosPeriodo, 
				@SaldoFavor,            
				@Notas1, 
				@Notas2, 
				@Notas3,
				@ComisionApertura,
				@MontoCredito,
				@PagoCapital,
				@PagoIntereses, 
				@PagoIVAIntereses ,
				@FechaCorte,            
				@RFC_E, 
				@NOMBRE_E, 
				@DATOS_E, 
				GETDATE(),
				@Consecutivo,@CAT,
				@SaldoInicialProximoPeriodo,
				@SaldoFinalProximoPeriodo,
				@RegimenFiscEmisor,
				@RazonSocialEmisor,
				@RegimenFiscReceptor,
				@CpReceptor)            
        
Fetch Next From  crsEncabezado Into @idContrato   
End  --Termina cursor para los encabezados            
Close crsEncabezado              
Deallocate crsEncabezado             
            
 --Elimina la tabla temporal            
 --drop table #Cargos 