-- -----------------------------------------------
/* database */
create database tunnel_ethereum_mainnet_accounts;
use tunnel_ethereum_mainnet_accounts;

/* create user */
create user 'tunnel_accounts'@'localhost' identified by 'Weinvent123!!!';
-- create user 'tunnel_accounts'@'%' identified by 'Weinvent123!!!';

-- -----------------------------------------------
/* Addresses, for account server and internal account */
CREATE TABLE IF NOT EXISTS `addresses` (
 `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
 `address` CHAR(42) NOT NULL,
 `keyjson` VARCHAR(1024) NOT NULL DEFAULT "", /* `keyjson` TEXT NOT NULL */
 `password` VARCHAR(256) NOT NULL DEFAULT "", /* password for keystore */
 `name` VARCHAR(128) NOT NULL DEFAULT "", /* name to mark the address */

 PRIMARY KEY (`id`),
 UNIQUE KEY (`address`)
)engine=innodb row_format=compressed;

-- -----------------------------------------------
/* Grant */
grant select on tunnel_ethereum_mainnet_accounts.addresses to 'tunnel_accounts'@'localhost';
grant insert on tunnel_ethereum_mainnet_accounts.addresses to 'tunnel_accounts'@'localhost';
-- grant all on tunnel_ethereum_mainnet_accounts.* to 'tunnel_accounts'@'localhost';
