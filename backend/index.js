const fs = require("fs");
const path = require("path");
const express = require("express");
const admin = require("firebase-admin");

const PORT = process.env.PORT || 8080;
const ALLOWED_DOMAIN = process.env.ALLOWED_DOMAIN || "marcopescaimport.com";
const DEFAULT_ANNUAL_DAYS = Number(process.env.DEFAULT_ANNUAL_DAYS || "22");

const REQUESTS_COLLECTION = "requests";
const BALANCES_COLLECTION = "vacation_balances";
const BALANCE_ADJUSTMENTS_COLLECTION = "vacation_balance_adjustments";
const HOLIDAYS_COLLECTION = "holidays";
const DEPARTMENTS_COLLECTION = "departments";
const USER_SETTINGS_COLLECTION = "user_settings";
const DEFAULT_WORKING_DAYS = [1, 2, 3, 4, 5];

admin.initializeApp();
const db = admin.firestore();

const usersPath = path.join(__dirname, "users.json");
let usersList = [];
try {
  const raw = fs.readFileSync(usersPath, "utf-8");
  usersList = JSON.parse(raw);
} catch (err) {
  console.error("No se pudo leer users.json", err);
}

const usersByEmail = new Map(usersList.map((u) => [u.email.toLowerCase(), u]));
const uidByEmailCache = new Map();
const userByUidCache = new Map();

const app = express();
app.use(express.json({ limit: "1mb" }));

app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type"
  );
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PATCH, PUT, OPTIONS");
  if (req.method === "OPTIONS") {
    return res.status(204).end();
  }
  next();
});

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.get("/me", authMiddleware, (req, res) => {
  res.json({
    uid: req.user.uid,
    email: req.user.email,
    role: req.user.role,
    departamentoId: req.user.departamentoId || null,
    displayName: req.user.displayName || null,
  });
});

app.get("/requests", authMiddleware, async (req, res) => {
  try {
    const { user } = req;
    const requestedUserId = normalizeText(req.query.userId);
    const requestedDept = normalizeText(req.query.departamentoId);
    const status = normalizeText(req.query.status);

    let query = db.collection(REQUESTS_COLLECTION);

    if (user.role === "empleado") {
      query = query.where("userId", "==", user.uid);
    } else if (user.role === "responsable") {
      query = query.where("departamentoId", "==", user.departamentoId || "");
    } else if (user.role === "jefe" || user.role === "admin_sistema") {
      if (requestedUserId) {
        query = query.where("userId", "==", requestedUserId);
      } else if (requestedDept) {
        query = query.where("departamentoId", "==", requestedDept);
      }
    }

    if (status) {
      query = query.where("estado", "==", status);
    }

    const snapshot = await query.limit(500).get();
    const items = snapshot.docs
      .map((doc) => mapRequestDoc(doc))
      .sort((a, b) => {
        const ad = Date.parse(a.createdAt || "") || 0;
        const bd = Date.parse(b.createdAt || "") || 0;
        return bd - ad;
      });

    const itemsWithEstimates = await Promise.all(
      items.map(async (item) => {
        if (item.estado === "pendiente") {
          const start = parseDateInput(item.fechaInicioStr);
          const end = parseDateInput(item.fechaFinStr);
          if (start && end) {
            item.diasEstimados = await countConsumableDays(
              start,
              end,
              item.userId
            );
          }
        }
        return item;
      })
    );

    res.json({ items: itemsWithEstimates });
  } catch (err) {
    console.error("requests_list_error", err);
    res.status(500).json({ error: "requests_list_error" });
  }
});

app.post("/requests", authMiddleware, async (req, res) => {
  try {
    if (!["empleado", "responsable", "jefe", "admin_sistema"].includes(req.user.role)) {
      return res.status(403).json({ error: "forbidden" });
    }

    const payload = req.body || {};
    const start = parseDateInput(payload.fechaInicio);
    const end = parseDateInput(payload.fechaFin);
    if (!start || !end) {
      return res.status(400).json({ error: "invalid_dates" });
    }
    if (start > end) {
      return res.status(400).json({ error: "invalid_range" });
    }

    const overlap = await hasOverlap(req.user.uid, start, end, null);
    if (overlap) {
      return res.status(400).json({ error: "overlap" });
    }

    const docData = {
      userId: req.user.uid,
      userEmail: req.user.email,
      userDisplayName: req.user.displayName || null,
      userRole: req.user.role,
      departamentoId: req.user.departamentoId || null,
      tipo: "vacaciones",
      fechaInicio: admin.firestore.Timestamp.fromDate(start),
      fechaFin: admin.firestore.Timestamp.fromDate(end),
      fechaInicioStr: toDateKey(start),
      fechaFinStr: toDateKey(end),
      estado: "pendiente",
      aprobadorId: null,
      fechaAprobacion: null,
      notas: normalizeText(payload.notas) || null,
      diasConsumidos: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const docRef = await db.collection(REQUESTS_COLLECTION).add(docData);
    res.json({ id: docRef.id });
  } catch (err) {
    console.error("requests_create_error", err);
    res.status(500).json({ error: "requests_create_error" });
  }
});

app.patch("/requests/:id", authMiddleware, async (req, res) => {
  try {
    const docRef = db.collection(REQUESTS_COLLECTION).doc(req.params.id);
    const doc = await docRef.get();
    if (!doc.exists) {
      return res.status(404).json({ error: "not_found" });
    }

    const data = doc.data() || {};
    if (req.user.role === "empleado" && data.userId !== req.user.uid) {
      return res.status(403).json({ error: "forbidden" });
    }

    const start = parseDateInput(req.body?.fechaInicio || data.fechaInicioStr);
    const end = parseDateInput(req.body?.fechaFin || data.fechaFinStr);
    if (!start || !end) {
      return res.status(400).json({ error: "invalid_dates" });
    }
    if (start > end) {
      return res.status(400).json({ error: "invalid_range" });
    }

    const overlap = await hasOverlap(
      data.userId,
      start,
      end,
      doc.id
    );
    if (overlap) {
      return res.status(400).json({ error: "overlap" });
    }

    const updates = {
      fechaInicio: admin.firestore.Timestamp.fromDate(start),
      fechaFin: admin.firestore.Timestamp.fromDate(end),
      fechaInicioStr: toDateKey(start),
      fechaFinStr: toDateKey(end),
      notas: normalizeText(req.body?.notas) || data.notas || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (data.estado === "aprobada") {
      const consumed = Number(data.diasConsumidos || 0);
      if (consumed > 0) {
        await adjustBalance(data.userId, -consumed);
      }
      updates.estado = "pendiente";
      updates.aprobadorId = null;
      updates.fechaAprobacion = null;
      updates.diasConsumidos = 0;
    }

    await docRef.update(updates);
    res.json({ ok: true });
  } catch (err) {
    console.error("requests_update_error", err);
    res.status(500).json({ error: "requests_update_error" });
  }
});

app.post("/requests/:id/approve", authMiddleware, async (req, res) => {
  try {
    const docRef = db.collection(REQUESTS_COLLECTION).doc(req.params.id);
    const doc = await docRef.get();
    if (!doc.exists) {
      return res.status(404).json({ error: "not_found" });
    }

    const data = doc.data() || {};
    if (!canApprove(req.user, data)) {
      return res.status(403).json({ error: "forbidden" });
    }
    if (data.estado !== "pendiente") {
      return res.status(400).json({ error: "invalid_state" });
    }

    const start = timestampToDate(data.fechaInicio, data.fechaInicioStr);
    const end = timestampToDate(data.fechaFin, data.fechaFinStr);
    if (!start || !end) {
      return res.status(400).json({ error: "invalid_dates" });
    }

    const overlap = await hasOverlap(data.userId, start, end, doc.id);
    if (overlap) {
      return res.status(400).json({ error: "overlap" });
    }

    const diasConsumidos = await countConsumableDays(
      start,
      end,
      data.userId
    );
    await adjustBalance(data.userId, diasConsumidos);

    await docRef.update({
      estado: "aprobada",
      aprobadorId: req.user.email,
      fechaAprobacion: admin.firestore.FieldValue.serverTimestamp(),
      diasConsumidos,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ ok: true, diasConsumidos });
  } catch (err) {
    console.error("requests_approve_error", err);
    res.status(500).json({ error: "requests_approve_error" });
  }
});

app.post("/requests/:id/reject", authMiddleware, async (req, res) => {
  try {
    const docRef = db.collection(REQUESTS_COLLECTION).doc(req.params.id);
    const doc = await docRef.get();
    if (!doc.exists) {
      return res.status(404).json({ error: "not_found" });
    }

    const data = doc.data() || {};
    if (!canApprove(req.user, data)) {
      return res.status(403).json({ error: "forbidden" });
    }
    if (data.estado !== "pendiente") {
      return res.status(400).json({ error: "invalid_state" });
    }

    await docRef.update({
      estado: "rechazada",
      aprobadorId: req.user.email,
      fechaAprobacion: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ ok: true });
  } catch (err) {
    console.error("requests_reject_error", err);
    res.status(500).json({ error: "requests_reject_error" });
  }
});

app.get("/balances", authMiddleware, async (req, res) => {
  try {
    let scopedUsers = [];
    if (req.user.role === "empleado") {
      const current = usersByEmail.get(req.user.email.toLowerCase());
      if (current) {
        scopedUsers = [current];
      }
    } else if (req.user.role === "responsable") {
      scopedUsers = usersList.filter(
        (u) =>
          u.departamentoId &&
          req.user.departamentoId &&
          u.departamentoId === req.user.departamentoId
      );
    } else {
      scopedUsers = usersList;
    }

    const items = await Promise.all(
      scopedUsers.map(async (u) => {
        const email = (u.email || "").toLowerCase();
        const uid = await getUidByEmail(email);
        if (!uid) return null;
        const balance = await getBalance(uid);
        return {
          userId: uid,
          email,
          displayName: u.displayName || null,
          departamentoId: u.departamentoId || null,
          ...balance,
        };
      })
    );

    res.json({ items: items.filter(Boolean) });
  } catch (err) {
    console.error("balances_list_error", err);
    res.status(500).json({ error: "balances_list_error" });
  }
});

app.get("/balances/:userId", authMiddleware, async (req, res) => {
  try {
    const userId = normalizeText(req.params.userId);
    if (!userId) {
      return res.status(400).json({ error: "missing_user" });
    }

    if (req.user.role === "empleado" && userId !== req.user.uid) {
      return res.status(403).json({ error: "forbidden" });
    }

    const balance = await getBalance(userId);
    res.json({ balance });
  } catch (err) {
    console.error("balances_get_error", err);
    res.status(500).json({ error: "balances_get_error" });
  }
});

app.post("/balances/:userId/adjust", authMiddleware, async (req, res) => {
  try {
    if (
      !["admin_sistema", "jefe", "responsable"].includes(req.user.role)
    ) {
      return res.status(403).json({ error: "forbidden" });
    }

    const userId = normalizeText(req.params.userId);
    if (!userId) {
      return res.status(400).json({ error: "missing_user" });
    }

    if (req.user.role === "responsable") {
      const target = await getUserEntryByUid(userId);
      if (
        !target ||
        !req.user.departamentoId ||
        target.departamentoId !== req.user.departamentoId
      ) {
        return res.status(403).json({ error: "forbidden" });
      }
    }

    const diasAsignadosAnualRaw = req.body?.diasAsignadosAnual;
    const diasArrastradosRaw = req.body?.diasArrastrados;
    const deltaExtraRaw = req.body?.deltaExtra;
    const comentario = normalizeText(req.body?.comentario) || null;

    const updates = {};
    if (diasAsignadosAnualRaw !== undefined && diasAsignadosAnualRaw !== null) {
      const value = Number(diasAsignadosAnualRaw);
      if (!Number.isFinite(value) || value < 0) {
        return res.status(400).json({ error: "invalid_dias_asignados" });
      }
      updates.diasAsignadosAnual = Math.round(value);
    }
    if (diasArrastradosRaw !== undefined && diasArrastradosRaw !== null) {
      const value = Number(diasArrastradosRaw);
      if (!Number.isFinite(value) || value < 0) {
        return res.status(400).json({ error: "invalid_dias_arrastrados" });
      }
      updates.diasArrastrados = Math.round(value);
    }

    let deltaExtra = 0;
    if (deltaExtraRaw !== undefined && deltaExtraRaw !== null && deltaExtraRaw !== "") {
      const value = Number(deltaExtraRaw);
      if (!Number.isFinite(value)) {
        return res.status(400).json({ error: "invalid_delta_extra" });
      }
      deltaExtra = Math.round(value);
    }

    if (deltaExtra !== 0 && !comentario) {
      return res.status(400).json({ error: "missing_comment" });
    }

    const balance = await getBalance(userId);
    const diasAsignadosAnual =
      updates.diasAsignadosAnual ?? balance.diasAsignadosAnual;
    const diasArrastrados =
      updates.diasArrastrados ?? balance.diasArrastrados;
    const diasExtra = Math.max(0, (balance.diasExtra || 0) + deltaExtra);
    const diasConsumidos = balance.diasConsumidos;
    const diasDisponibles =
      diasAsignadosAnual + diasArrastrados + diasExtra - diasConsumidos;

    const balanceUpdate = {
      diasAsignadosAnual,
      diasArrastrados,
      diasExtra,
      diasConsumidos,
      diasDisponibles,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (deltaExtra !== 0 || comentario) {
      balanceUpdate.lastExtraComentario = comentario || null;
      balanceUpdate.lastExtraDelta = deltaExtra;
      balanceUpdate.lastExtraBy = req.user.email;
      balanceUpdate.lastExtraAt = admin.firestore.FieldValue.serverTimestamp();
    }

    await db
      .collection(BALANCES_COLLECTION)
      .doc(userId)
      .set(
        balanceUpdate,
        { merge: true }
      );

    if (deltaExtra !== 0 || comentario) {
      await db.collection(BALANCE_ADJUSTMENTS_COLLECTION).add({
        userId,
        deltaExtra,
        comentario,
        diasAsignadosAnual,
        diasArrastrados,
        createdBy: req.user.email,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    res.json({
      ok: true,
      balance: {
        userId,
        diasAsignadosAnual,
        diasArrastrados,
        diasExtra,
        diasConsumidos,
        diasDisponibles,
      },
    });
  } catch (err) {
    console.error("balances_adjust_error", err);
    res.status(500).json({ error: "balances_adjust_error" });
  }
});

app.get("/balances/:userId/adjustments", authMiddleware, async (req, res) => {
  try {
    const userId = normalizeText(req.params.userId);
    if (!userId) {
      return res.status(400).json({ error: "missing_user" });
    }

    if (req.user.role === "empleado" && userId !== req.user.uid) {
      return res.status(403).json({ error: "forbidden" });
    }

    if (req.user.role === "responsable") {
      const target = await getUserEntryByUid(userId);
      if (
        !target ||
        !req.user.departamentoId ||
        target.departamentoId !== req.user.departamentoId
      ) {
        return res.status(403).json({ error: "forbidden" });
      }
    }

    const snapshot = await db
      .collection(BALANCE_ADJUSTMENTS_COLLECTION)
      .where("userId", "==", userId)
      .get();

    const items = snapshot.docs
      .map((doc) => {
        const data = doc.data() || {};
        return {
          id: doc.id,
          userId: data.userId || null,
          deltaExtra: Number(data.deltaExtra || 0),
          comentario: data.comentario || null,
          createdBy: data.createdBy || null,
          createdAt: toIsoString(data.createdAt),
        };
      })
      .sort((a, b) => {
        const ad = Date.parse(a.createdAt || "") || 0;
        const bd = Date.parse(b.createdAt || "") || 0;
        return bd - ad;
      });

    res.json({ items });
  } catch (err) {
    console.error("balances_adjustments_list_error", err);
    res.status(500).json({ error: "balances_adjustments_list_error" });
  }
});

app.get("/calendar", authMiddleware, async (req, res) => {
  try {
    const requestedDept = normalizeText(req.query.departamentoId);
    const requestedDeptList = normalizeText(req.query.departamentoIds);
    const deptIds = requestedDeptList
      ? requestedDeptList
          .split(",")
          .map((d) => d.trim())
          .filter(Boolean)
      : requestedDept
      ? [requestedDept]
      : [];
    const includePending = normalizeText(req.query.includePending) === "1";
    const start = parseDateInput(req.query.from);
    const end = parseDateInput(req.query.to);
    if (!start || !end) {
      return res.status(400).json({ error: "invalid_dates" });
    }

    let query = db.collection(REQUESTS_COLLECTION);

    if (req.user.role === "empleado") {
      query = query.where("userId", "==", req.user.uid);
    } else if (req.user.role === "responsable") {
      query = query.where("departamentoId", "==", req.user.departamentoId || "");
    } else {
      if (deptIds.length === 1) {
        query = query.where("departamentoId", "==", deptIds[0]);
      } else if (deptIds.length > 1 && deptIds.length <= 10) {
        query = query.where("departamentoId", "in", deptIds);
      }
    }

    const snapshot = await query.get();
    const items = snapshot.docs
      .map((doc) => mapRequestDoc(doc))
      .filter((item) => {
        if (includePending) {
          if (!["aprobada", "pendiente"].includes(item.estado)) {
            return false;
          }
        } else {
          if (item.estado !== "aprobada") {
            return false;
          }
        }
        if (
          deptIds.length > 0 &&
          req.user.role !== "empleado" &&
          req.user.role !== "responsable"
        ) {
          if (!deptIds.includes(item.departamentoId || "")) {
            return false;
          }
        }
        const s = parseDateInput(item.fechaInicioStr);
        const e = parseDateInput(item.fechaFinStr);
        if (!s || !e) return false;
        return s <= end && e >= start;
      });

    const workingDaysCache = new Map();
    const enriched = await Promise.all(
      items.map(async (item) => {
        if (!item.userId) return item;
        if (!workingDaysCache.has(item.userId)) {
          workingDaysCache.set(
            item.userId,
            await getUserWorkingDays(item.userId)
          );
        }
        return {
          ...item,
          workingDays: workingDaysCache.get(item.userId),
        };
      })
    );

    res.json({ items: enriched });
  } catch (err) {
    console.error("calendar_error", err);
    res.status(500).json({ error: "calendar_error" });
  }
});

app.get("/holidays", authMiddleware, async (req, res) => {
  try {
    const year = Number(req.query.year || 0);
    if (!Number.isFinite(year) || year <= 0) {
      return res.status(400).json({ error: "invalid_year" });
    }

    const snapshot = await db
      .collection(HOLIDAYS_COLLECTION)
      .where("year", "==", year)
      .get();

    const items = snapshot.docs.map((doc) => doc.data());
    res.json({ items });
  } catch (err) {
    console.error("holidays_list_error", err);
    res.status(500).json({ error: "holidays_list_error" });
  }
});

app.put("/holidays", authMiddleware, async (req, res) => {
  try {
    if (!["admin_sistema", "jefe"].includes(req.user.role)) {
      return res.status(403).json({ error: "forbidden" });
    }

    const year = Number(req.body?.year || 0);
    const dates = Array.isArray(req.body?.dates) ? req.body.dates : [];
    if (!Number.isFinite(year) || year <= 0) {
      return res.status(400).json({ error: "invalid_year" });
    }

    const cleaned = dates
      .map((d) => normalizeText(d))
      .filter((d) => !!parseDateInput(d));

    const snapshot = await db
      .collection(HOLIDAYS_COLLECTION)
      .where("year", "==", year)
      .get();

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    cleaned.forEach((date) => {
      const docRef = db.collection(HOLIDAYS_COLLECTION).doc();
      batch.set(docRef, { year, date });
    });

    await batch.commit();
    res.json({ ok: true, count: cleaned.length });
  } catch (err) {
    console.error("holidays_update_error", err);
    res.status(500).json({ error: "holidays_update_error" });
  }
});

app.get("/departments", authMiddleware, async (_req, res) => {
  try {
    const snapshot = await db.collection(DEPARTMENTS_COLLECTION).get();
    const items = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    res.json({ items });
  } catch (err) {
    console.error("departments_list_error", err);
    res.status(500).json({ error: "departments_list_error" });
  }
});

app.get("/users", authMiddleware, async (req, res) => {
  try {
    let scopedUsers = [];
    if (req.user.role === "empleado") {
      const current = usersByEmail.get(req.user.email.toLowerCase());
      if (current) {
        scopedUsers = [current];
      }
    } else if (req.user.role === "responsable") {
      scopedUsers = usersList.filter(
        (u) =>
          u.departamentoId &&
          req.user.departamentoId &&
          u.departamentoId === req.user.departamentoId
      );
    } else {
      scopedUsers = usersList;
    }

    const items = await Promise.all(
      scopedUsers.map(async (u) => {
        const email = (u.email || "").toLowerCase();
        const uid = await getUidByEmail(email);
        if (!uid) return null;
        const workingDays = await getUserWorkingDays(uid);
        return {
          userId: uid,
          email,
          displayName: u.displayName || null,
          role: u.role || null,
          departamentoId: u.departamentoId || null,
          workingDays,
        };
      })
    );

    res.json({ items: items.filter(Boolean) });
  } catch (err) {
    console.error("users_list_error", err);
    res.status(500).json({ error: "users_list_error" });
  }
});

app.put("/users/:userId/working-days", authMiddleware, async (req, res) => {
  try {
    if (
      !["admin_sistema", "jefe", "responsable"].includes(req.user.role)
    ) {
      return res.status(403).json({ error: "forbidden" });
    }

    const userId = normalizeText(req.params.userId);
    if (!userId) {
      return res.status(400).json({ error: "missing_user" });
    }

    if (req.user.role === "responsable") {
      const target = await getUserEntryByUid(userId);
      if (
        !target ||
        !req.user.departamentoId ||
        target.departamentoId !== req.user.departamentoId
      ) {
        return res.status(403).json({ error: "forbidden" });
      }
    }

    const workingDays = normalizeWorkingDays(req.body?.workingDays);
    if (workingDays.length === 0) {
      return res.status(400).json({ error: "invalid_working_days" });
    }

    await db
      .collection(USER_SETTINGS_COLLECTION)
      .doc(userId)
      .set(
        {
          workingDays,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: req.user.email,
        },
        { merge: true }
      );

    res.json({ ok: true, workingDays });
  } catch (err) {
    console.error("users_working_days_error", err);
    res.status(500).json({ error: "users_working_days_error" });
  }
});

app.post("/departments", authMiddleware, async (req, res) => {
  try {
    if (!["admin_sistema", "jefe"].includes(req.user.role)) {
      return res.status(403).json({ error: "forbidden" });
    }

    const name = normalizeText(req.body?.name);
    const responsableId = normalizeText(req.body?.responsableId) || null;
    if (!name) {
      return res.status(400).json({ error: "missing_name" });
    }

    const docRef = await db.collection(DEPARTMENTS_COLLECTION).add({
      name,
      responsableId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ id: docRef.id });
  } catch (err) {
    console.error("departments_create_error", err);
    res.status(500).json({ error: "departments_create_error" });
  }
});

function normalizeText(value) {
  if (value === null || value === undefined) return "";
  return value.toString().trim();
}

function toIsoString(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  return value.toString();
}

function parseDateInput(value) {
  const raw = normalizeText(value);
  if (!raw) return null;
  const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (!year || !month || !day) return null;
  const date = new Date(Date.UTC(year, month - 1, day));
  return Number.isNaN(date.getTime()) ? null : date;
}

function toDateKey(date) {
  const y = date.getUTCFullYear().toString().padStart(4, "0");
  const m = (date.getUTCMonth() + 1).toString().padStart(2, "0");
  const d = date.getUTCDate().toString().padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function timestampToDate(ts, fallbackStr) {
  if (ts && typeof ts.toDate === "function") {
    return ts.toDate();
  }
  return parseDateInput(fallbackStr);
}

function mapRequestDoc(doc) {
  const data = doc.data() || {};
  const email = data.userEmail || null;
  const displayName =
    data.userDisplayName ||
    (email ? displayNameFor(email) : null) ||
    null;
  const userRole =
    data.userRole ||
    (email ? usersByEmail.get(email.toLowerCase())?.role : null) ||
    null;
  return {
    id: doc.id,
    userId: data.userId || null,
    userEmail: email,
    userDisplayName: displayName,
    userRole,
    departamentoId: data.departamentoId || null,
    tipo: data.tipo || "vacaciones",
    fechaInicioStr: data.fechaInicioStr || null,
    fechaFinStr: data.fechaFinStr || null,
    estado: data.estado || "pendiente",
    aprobadorId: data.aprobadorId || null,
    fechaAprobacion: data.fechaAprobacion || null,
    notas: data.notas || null,
    diasConsumidos: Number(data.diasConsumidos || 0),
    createdAt: toIsoString(data.createdAt),
  };
}

function displayNameFor(email) {
  if (!email) return null;
  const user = usersByEmail.get(email.toLowerCase());
  if (user && user.displayName) return user.displayName;
  return null;
}

async function getUidByEmail(email) {
  if (!email) return null;
  const cached = uidByEmailCache.get(email);
  if (cached) return cached;
  try {
    const record = await admin.auth().getUserByEmail(email);
    if (record?.uid) {
      uidByEmailCache.set(email, record.uid);
      userByUidCache.set(record.uid, {
        uid: record.uid,
        email: email.toLowerCase(),
        ...usersByEmail.get(email.toLowerCase()),
      });
      return record.uid;
    }
  } catch (err) {
    console.error("get_uid_error", err);
  }
  return null;
}

async function getUserEntryByUid(uid) {
  if (!uid) return null;
  const cached = userByUidCache.get(uid);
  if (cached) return cached;
  try {
    const record = await admin.auth().getUser(uid);
    const email = (record.email || "").toLowerCase();
    const entry = usersByEmail.get(email);
    const result = {
      uid,
      email,
      displayName: entry?.displayName || null,
      departamentoId: entry?.departamentoId || null,
      role: entry?.role || null,
    };
    userByUidCache.set(uid, result);
    uidByEmailCache.set(email, uid);
    return result;
  } catch (err) {
    console.error("get_user_by_uid_error", err);
    return null;
  }
}

function canApprove(user, requestData) {
  const requesterRole = getRequestUserRole(requestData);
  if (user.role === "admin_sistema") {
    return false;
  }
  if (user.role === "jefe") {
    return true;
  }
  if (user.role === "responsable") {
    if (requestData.userId && requestData.userId === user.uid) {
      return false;
    }
    if (["responsable", "jefe", "admin_sistema"].includes(requesterRole)) {
      return false;
    }
    return (
      requestData.departamentoId &&
      user.departamentoId &&
      requestData.departamentoId === user.departamentoId
    );
  }
  return false;
}

function getRequestUserRole(requestData) {
  const role = normalizeText(requestData.userRole);
  if (role) return role;
  const email = normalizeText(requestData.userEmail).toLowerCase();
  const entry = usersByEmail.get(email);
  return entry?.role || "";
}

async function hasOverlap(userId, start, end, excludeId) {
  const snapshot = await db
    .collection(REQUESTS_COLLECTION)
    .where("userId", "==", userId)
    .get();

  for (const doc of snapshot.docs) {
    if (excludeId && doc.id === excludeId) continue;
    const data = doc.data() || {};
    if (!["pendiente", "aprobada"].includes(data.estado)) {
      continue;
    }
    const s = timestampToDate(data.fechaInicio, data.fechaInicioStr);
    const e = timestampToDate(data.fechaFin, data.fechaFinStr);
    if (!s || !e) continue;
    if (s <= end && e >= start) {
      return true;
    }
  }

  return false;
}

async function countConsumableDays(start, end, userId) {
  const holidaySet = await loadHolidaySet(start, end);
  const workingDays = await getUserWorkingDaysForRange(start, end, userId);
  const workingSet = new Set(workingDays);
  let count = 0;
  let cursor = new Date(start.getTime());
  while (cursor <= end) {
    const key = toDateKey(cursor);
    if (workingSet.has(toIsoWeekday(cursor)) && !holidaySet.has(key)) {
      count += 1;
    }
    cursor = new Date(cursor.getTime() + 86400000);
  }
  return count;
}

function toIsoWeekday(date) {
  const day = date.getUTCDay();
  return day === 0 ? 7 : day;
}

async function loadHolidaySet(start, end) {
  const years = [];
  for (let y = start.getUTCFullYear(); y <= end.getUTCFullYear(); y += 1) {
    years.push(y);
  }

  const set = new Set();
  for (const year of years) {
    const snapshot = await db
      .collection(HOLIDAYS_COLLECTION)
      .where("year", "==", year)
      .get();
    snapshot.docs.forEach((doc) => {
      const data = doc.data() || {};
      const date = normalizeText(data.date);
      if (date) set.add(date);
    });
  }

  return set;
}

function normalizeWorkingDays(values) {
  if (!Array.isArray(values)) return [];
  const set = new Set();
  values.forEach((value) => {
    const num = Number(value);
    if (Number.isFinite(num) && num >= 1 && num <= 7) {
      set.add(Math.round(num));
    }
  });
  return Array.from(set).sort((a, b) => a - b);
}

async function getUserWorkingDays(userId) {
  if (!userId) return DEFAULT_WORKING_DAYS;
  const doc = await db.collection(USER_SETTINGS_COLLECTION).doc(userId).get();
  if (!doc.exists) return DEFAULT_WORKING_DAYS;
  const data = doc.data() || {};
  const cleaned = normalizeWorkingDays(data.workingDays);
  return cleaned.length > 0 ? cleaned : DEFAULT_WORKING_DAYS;
}

async function getUserWorkingDaysForRange(start, end, userId) {
  if (!userId) return DEFAULT_WORKING_DAYS;
  return getUserWorkingDays(userId);
}

async function getBalance(userId) {
  const docRef = db.collection(BALANCES_COLLECTION).doc(userId);
  const doc = await docRef.get();
  if (!doc.exists) {
    const initial = {
      diasAsignadosAnual: DEFAULT_ANNUAL_DAYS,
      diasArrastrados: 0,
      diasExtra: 0,
      diasConsumidos: 0,
      diasDisponibles: DEFAULT_ANNUAL_DAYS,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await docRef.set(initial);
    return { userId, ...initial };
  }

  const data = doc.data() || {};
  const diasAsignadosAnual = Number(data.diasAsignadosAnual || DEFAULT_ANNUAL_DAYS);
  const diasArrastrados = Number(data.diasArrastrados || 0);
  const diasExtra = Number(data.diasExtra || 0);
  const diasConsumidos = Number(data.diasConsumidos || 0);
  const diasDisponibles =
    diasAsignadosAnual + diasArrastrados + diasExtra - diasConsumidos;

  return {
    userId,
    diasAsignadosAnual,
    diasArrastrados,
    diasExtra,
    diasConsumidos,
    diasDisponibles,
    lastExtraComentario: data.lastExtraComentario || null,
    lastExtraDelta: Number(data.lastExtraDelta || 0),
    lastExtraBy: data.lastExtraBy || null,
    lastExtraAt: toIsoString(data.lastExtraAt),
  };
}

async function adjustBalance(userId, deltaConsumidos) {
  const docRef = db.collection(BALANCES_COLLECTION).doc(userId);
  const balance = await getBalance(userId);
  const diasConsumidos = Math.max(0, Number(balance.diasConsumidos || 0) + deltaConsumidos);
  const diasAsignadosAnual = Number(balance.diasAsignadosAnual || DEFAULT_ANNUAL_DAYS);
  const diasArrastrados = Number(balance.diasArrastrados || 0);
  const diasExtra = Number(balance.diasExtra || 0);
  const diasDisponibles =
    diasAsignadosAnual + diasArrastrados + diasExtra - diasConsumidos;

  await docRef.set(
    {
      diasAsignadosAnual,
      diasArrastrados,
      diasExtra,
      diasConsumidos,
      diasDisponibles,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function authMiddleware(req, res, next) {
  try {
    const auth = req.headers.authorization || "";
    if (!auth.startsWith("Bearer ")) {
      return res.status(401).json({ error: "missing_token" });
    }

    const token = auth.replace("Bearer ", "").trim();
    const decoded = await admin.auth().verifyIdToken(token);
    const email = (decoded.email || "").toLowerCase();
    if (!email.endsWith(`@${ALLOWED_DOMAIN}`)) {
      return res.status(403).json({ error: "domain_not_allowed" });
    }

    const user = usersByEmail.get(email);
    if (!user) {
      return res.status(403).json({ error: "user_not_allowed" });
    }

    req.user = {
      uid: decoded.uid,
      email,
      role: user.role,
      departamentoId: user.departamentoId || null,
      displayName: user.displayName || null,
    };
    next();
  } catch (err) {
    console.error("auth_error", err);
    res.status(401).json({ error: "invalid_token" });
  }
}

app.listen(PORT, () => {
  console.log(`Backend running on port ${PORT}`);
});
