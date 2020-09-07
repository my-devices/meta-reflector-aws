--
-- createtables.sql
--
-- Create SQL tables for OSP Auth bundle and reflector device database.
-- Will also create user "admin" (password "admin")
-- with administrator permissions ("bundleAdmin" and "authAdmin") and
-- access to all devices ("reflector.device:*", "reflector.domain:*").
--

--
-- User Authentication
--

CREATE TABLE auth_user
(
	username VARCHAR(64) PRIMARY KEY NOT NULL,
	password VARCHAR(64) NOT NULL,
	tenant VARCHAR(64),
	domain VARCHAR(64),
	firstName VARCHAR(64),
	lastName VARCHAR(64),
	organization VARCHAR(64),
	email VARCHAR(256),
	tags VARCHAR(256),
	lastLogin VARCHAR(32),
	createdBy VARCHAR(64),
	created VARCHAR(32)
);

CREATE TABLE auth_role
(
	rolename VARCHAR(64) PRIMARY KEY
);

CREATE TABLE auth_user_roles
(
	username VARCHAR(64) NOT NULL REFERENCES auth_user(username) ON DELETE CASCADE,
	rolename VARCHAR(64) NOT NULL REFERENCES auth_role(rolename) ON DELETE CASCADE
);

CREATE TABLE auth_user_permissions
(
	username VARCHAR(64) NOT NULL REFERENCES auth_user(username) ON DELETE CASCADE,
	permission VARCHAR(64) NOT NULL
);

CREATE TABLE auth_role_permissions
(
	rolename VARCHAR(64) NOT NULL REFERENCES auth_role(rolename) ON DELETE CASCADE,
	permission VARCHAR(64) NOT NULL
);

CREATE TABLE auth_user_attributes
(
	username VARCHAR(64) NOT NULL REFERENCES auth_user(username) ON DELETE CASCADE,
	attribute VARCHAR(64) NOT NULL,
	value VARCHAR(4096) NOT NULL
);

CREATE INDEX auth_user_roles_index ON auth_user_roles(username);
CREATE INDEX auth_user_permissions_index ON auth_user_permissions(username);
CREATE INDEX auth_role_permissions_index ON auth_role_permissions(rolename);
CREATE INDEX auth_user_attributes_index ON auth_user_attributes(username);
CREATE UNIQUE INDEX auth_user_attributes_attr_index ON auth_user_attributes(username, attribute);
CREATE INDEX auth_user_attributes_value_index ON auth_user_attributes(attribute, value(64));

INSERT INTO auth_user (username, password) VALUES("admin", "3d29e163b9107fcb31077b45b47026e2");

INSERT INTO auth_role VALUES("systemAdmin");
INSERT INTO auth_role VALUES("reflectorAdmin");
INSERT INTO auth_role VALUES("user");
INSERT INTO auth_role VALUES("powerUser");

INSERT INTO auth_role_permissions VALUES("systemAdmin", "bundleAdmin");
INSERT INTO auth_role_permissions VALUES("systemAdmin", "authAdmin");
INSERT INTO auth_role_permissions VALUES("reflectorAdmin", "reflector.device:*");
INSERT INTO auth_role_permissions VALUES("reflectorAdmin", "reflector.domain:*");
INSERT INTO auth_role_permissions VALUES("reflectorAdmin", "reflector.device.*");
INSERT INTO auth_role_permissions VALUES("reflectorAdmin", "domainAdmin");
INSERT INTO auth_role_permissions VALUES("reflectorAdmin", "tenantAdmin");
INSERT INTO auth_role_permissions VALUES("powerUser", "reflector.device.*");
INSERT INTO auth_user_roles VALUES("admin", "systemAdmin");
INSERT INTO auth_user_roles VALUES("admin", "reflectorAdmin");

--
-- Reflector
--

CREATE TABLE reflector_systemprop
(
	name VARCHAR(64) NOT NULL,
	value VARCHAR(1024)
);

INSERT INTO reflector_systemprop VALUES ('schemaVersion', 9);

CREATE TABLE reflector_domain
(
	id VARCHAR(48) PRIMARY KEY NOT NULL,
	name VARCHAR(128),
	description VARCHAR(1024),
	tags VARCHAR(256),
	createdBy VARCHAR(64),
	created VARCHAR(32)
);

CREATE UNIQUE INDEX reflector_domain_index ON reflector_domain(id);

CREATE TABLE reflector_domainprop
(
	domain VARCHAR(48) NOT NULL,
	name VARCHAR(64) NOT NULL,
	value VARCHAR(4096),

	FOREIGN KEY (domain) REFERENCES reflector_domain (id) ON DELETE CASCADE
);

CREATE INDEX reflector_domainprop_domain_index ON reflector_domainprop(domain);
CREATE UNIQUE INDEX reflector_domainprop_prop_index ON reflector_domainprop(domain, name);

CREATE TABLE reflector_tenant
(
	id VARCHAR(48) PRIMARY KEY NOT NULL,
	name VARCHAR(128),
	description VARCHAR(1024),
	tags VARCHAR(256),
	createdBy VARCHAR(64),
	created VARCHAR(32)
);

CREATE UNIQUE INDEX reflector_tenant_index ON reflector_tenant(id);

CREATE TABLE reflector_tenantprop
(
	tenant VARCHAR(48) NOT NULL,
	name VARCHAR(64) NOT NULL,
	value VARCHAR(4096),

	FOREIGN KEY (tenant) REFERENCES reflector_tenant (id) ON DELETE CASCADE
);

CREATE INDEX reflector_tenantprop_tenant_index ON reflector_tenantprop(tenant);
CREATE UNIQUE INDEX reflector_tenantprop_prop_index ON reflector_tenantprop(tenant, name);

CREATE TABLE reflector_device
(
	id VARCHAR(48) PRIMARY KEY NOT NULL,
	name VARCHAR(128),
	description VARCHAR(1024),
	tags VARCHAR(256),
	type VARCHAR(64),
	version VARCHAR(32),
	parent VARCHAR(48),
	server VARCHAR(64),
	online BOOLEAN,
	protocol VARCHAR(16),
	lastConnect VARCHAR(32),
	host VARCHAR(64),
	port VARCHAR(8),
	domain VARCHAR(48) ,
	userAgent VARCHAR(256),
	hashedPassword VARCHAR(64),
	createdBy VARCHAR(64),
	created VARCHAR(32),
	category VARCHAR(256),
	site VARCHAR(256),
	serial VARCHAR(48),
	bytesTx BIGINT,
	bytesRx BIGINT,
	connects BIGINT,

	FOREIGN KEY (domain) REFERENCES reflector_domain (id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX reflector_device_index ON reflector_device(id, online);
CREATE INDEX reflector_device_category_index ON reflector_device(category);
CREATE INDEX reflector_device_site_index ON reflector_device(site);
CREATE INDEX reflector_device_serial_index ON reflector_device(serial);
CREATE INDEX reflector_device_createdBy_index ON reflector_device(createdBy);
CREATE INDEX reflector_device_created_index ON reflector_device(created);

CREATE TABLE reflector_deviceprop
(
	device VARCHAR(48) NOT NULL,
	name VARCHAR(64) NOT NULL,
	value VARCHAR(4096),

	FOREIGN KEY (device) REFERENCES reflector_device (id) ON DELETE CASCADE
);

CREATE INDEX reflector_deviceprop_device_index ON reflector_deviceprop(device);
CREATE UNIQUE INDEX reflector_deviceprop_prop_index ON reflector_deviceprop(device, name);
CREATE INDEX reflector_deviceprop_name_index ON reflector_deviceprop(name);

-- Trigger to delete device permission if referenced device is deleted
DELIMITER //
CREATE TRIGGER delete_device_permission AFTER DELETE ON reflector_device
FOR EACH ROW
BEGIN
DELETE FROM auth_user_permissions WHERE permission = CONCAT('reflector.device:', old.id);
DELETE FROM auth_role_permissions WHERE permission = CONCAT('reflector.device:', old.id);
END;//
