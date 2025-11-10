CREATE DATABASE  IF NOT EXISTS `TataLoan` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;
USE `TataLoan`;
-- MySQL dump 10.13  Distrib 8.0.40, for macos14 (arm64)
--
-- Host: localhost    Database: TataLoan
-- ------------------------------------------------------
-- Server version	9.1.0

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Dumping routines for database 'TataLoan'
--
/*!50003 DROP PROCEDURE IF EXISTS `sp_apply_all_repayments` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_0900_ai_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION' */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_apply_all_repayments`()
gen_repay_block: BEGIN
  DECLARE done2 INT DEFAULT 0;
  DECLARE v_repid BIGINT;

  DECLARE cur_reps CURSOR FOR SELECT repayment_id FROM repayments ORDER BY repayment_id;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done2 = 1;

  OPEN cur_reps;

  repay_loop: LOOP
    FETCH cur_reps INTO v_repid;
    IF done2 = 1 THEN LEAVE repay_loop; END IF;

    CALL sp_apply_repayment(v_repid);
  END LOOP repay_loop;

  CLOSE cur_reps;
END gen_repay_block ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `sp_apply_repayment` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_0900_ai_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION' */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_apply_repayment`(IN p_repayment_id BIGINT)
proc_block: BEGIN
  DECLARE v_loan_id BIGINT;
  DECLARE v_amt DECIMAL(14,2);
  DECLARE v_schedule_id BIGINT;
  DECLARE v_emi DECIMAL(14,2);
  DECLARE v_due DATE;
  DECLARE v_late_fee DECIMAL(10,2);
  DECLARE v_notfound INT DEFAULT 0;

  -- handler sets flag when SELECT ... INTO returns no row
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_notfound = 1;

  -- get repayment row
  SELECT loan_id, amount_paid INTO v_loan_id, v_amt FROM repayments WHERE repayment_id = p_repayment_id;
  IF v_loan_id IS NULL THEN
    LEAVE proc_block;
  END IF;

  -- loop allocating to earliest pending EMI
  alloc_loop: LOOP
    SET v_notfound = 0;
    SELECT schedule_id, emi_amount, due_date
      INTO v_schedule_id, v_emi, v_due
    FROM loan_schedule
    WHERE loan_id = v_loan_id AND status = 'Pending'
    ORDER BY due_date ASC
    LIMIT 1;

    IF v_notfound = 1 OR v_schedule_id IS NULL OR v_amt <= 0 THEN
      LEAVE alloc_loop;
    END IF;

    IF DATEDIFF(CURDATE(), v_due) > 10 THEN
      SET v_late_fee = 100;
    ELSE
      SET v_late_fee = 0;
    END IF;

    IF v_amt >= v_emi + v_late_fee THEN
      INSERT INTO repayment_allocations (repayment_id, schedule_id, amount_allocated, late_fee)
      VALUES (p_repayment_id, v_schedule_id, v_emi, v_late_fee);

      UPDATE loan_schedule SET status = 'Paid' WHERE schedule_id = v_schedule_id;

      SET v_amt = v_amt - v_emi - v_late_fee;
    ELSE
      -- partial allocation
      INSERT INTO repayment_allocations (repayment_id, schedule_id, amount_allocated, late_fee)
      VALUES (p_repayment_id, v_schedule_id, v_amt, v_late_fee);

      SET v_amt = 0;
    END IF;
  END LOOP alloc_loop;

  -- adjust loan outstanding by allocations created for this repayment
  UPDATE loans
  SET current_outstanding = current_outstanding - COALESCE(
    (SELECT SUM(amount_allocated) FROM repayment_allocations WHERE repayment_id = p_repayment_id),
    0
  )
  WHERE loan_id = v_loan_id;

  -- mark closed if nearly zero outstanding
  UPDATE loans
  SET status = 'Closed', current_outstanding = 0
  WHERE loan_id = v_loan_id AND current_outstanding <= 1.00;

END proc_block ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `sp_disburse_loan_v2` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_0900_ai_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION' */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_disburse_loan_v2`(IN p_loan_id BIGINT)
main_block: BEGIN
  DECLARE v_principal DECIMAL(14,2);
  DECLARE v_interest_rate DECIMAL(10,6);
  DECLARE v_tenure INT;
  DECLARE v_start_date DATE;
  DECLARE v_monthly_rate DECIMAL(10,6);
  DECLARE v_emi DECIMAL(18,6);
  DECLARE v_interest DECIMAL(18,6);
  DECLARE v_principal_comp DECIMAL(18,6);
  DECLARE v_balance DECIMAL(18,6);
  DECLARE v_due DATE;
  DECLARE i INT DEFAULT 1;

  SELECT principal_amount, interest_rate, tenure_months, start_date
  INTO v_principal, v_interest_rate, v_tenure, v_start_date
  FROM loans WHERE loan_id = p_loan_id;

  IF v_principal IS NULL THEN
    LEAVE main_block;
  END IF;

  SET v_monthly_rate = v_interest_rate / 1200;
  IF v_monthly_rate = 0 THEN
    SET v_emi = v_principal / v_tenure;
  ELSE
    SET v_emi = v_principal * v_monthly_rate * POW(1+v_monthly_rate, v_tenure) / (POW(1+v_monthly_rate, v_tenure)-1);
  END IF;

  SET v_balance = v_principal;

  -- idempotent: remove old schedule
  DELETE FROM loan_schedule WHERE loan_id = p_loan_id;

  WHILE i <= v_tenure DO
    SET v_interest = v_balance * v_monthly_rate;
    SET v_principal_comp = v_emi - v_interest;

    IF i = v_tenure THEN
      -- adjust final principal to clear rounding differences
      SET v_principal_comp = v_balance;
      SET v_emi = v_principal_comp + v_interest;
      SET v_balance = 0;
    ELSE
      SET v_balance = v_balance - v_principal_comp;
    END IF;

    SET v_due = DATE_ADD(v_start_date, INTERVAL i MONTH);

    INSERT INTO loan_schedule (
      loan_id, installment_no, due_date, emi_amount, principal_component, interest_component, balance_outstanding
    ) VALUES (p_loan_id, i, v_due, ROUND(v_emi,2), ROUND(v_principal_comp,2), ROUND(v_interest,2), ROUND(v_balance,2));

    SET i = i + 1;
  END WHILE;

END main_block ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `sp_generate_all_schedules` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_0900_ai_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION' */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_generate_all_schedules`()
gen_sched_block: BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE v_loan BIGINT;

  DECLARE cur_loans CURSOR FOR SELECT loan_id FROM loans ORDER BY loan_id;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  OPEN cur_loans;

  loan_loop: LOOP
    FETCH cur_loans INTO v_loan;
    IF done = 1 THEN LEAVE loan_loop; END IF;

    CALL sp_disburse_loan_v2(v_loan);
  END LOOP loan_loop;

  CLOSE cur_loans;
END gen_sched_block ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 DROP PROCEDURE IF EXISTS `sp_safe_repayment` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_0900_ai_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION' */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_safe_repayment`(IN p_loan_id BIGINT, IN p_amount DECIMAL(12,2))
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;
    INSERT INTO repayments (loan_id, payment_date, amount_paid, payment_mode)
    VALUES (p_loan_id, CURDATE(), p_amount, 'Bank Transfer');

    CALL sp_apply_repayment(LAST_INSERT_ID());
  COMMIT;
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2025-11-10 15:02:03
