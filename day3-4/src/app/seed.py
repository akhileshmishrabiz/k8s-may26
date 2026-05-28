import json
import os
import uuid
from pathlib import Path

from sqlalchemy import inspect, text

from app import db
from app.models.models import (
    Retro,
    RetroCard,
    RetroParticipant,
    Subtask,
    Team,
    TeamMember,
    Ticket,
    TicketComment,
    User,
)

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
ADMINS_FILE = DATA_DIR / "admins.json"
RETROS_FILE = DATA_DIR / "devops_retros.json"
TICKETS_FILE = DATA_DIR / "devops_tickets.json"
TEAMS_FILE = DATA_DIR / "devops_teams.json"

# Primary admin — kept for tests and backwards compatibility
ADMIN_EMAIL = "livingdevops@gmail.com"
ADMIN_USERNAME = "livingdevops"


def _load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _resolve_password(entry):
    env_key = entry.get("password_env")
    if env_key:
        env_value = os.getenv(env_key)
        if env_value:
            return env_value
    return entry["password"]


def load_admins():
    return _load_json(ADMINS_FILE)["admins"]


def load_devops_retros():
    return _load_json(RETROS_FILE)["retros"]


def load_devops_tickets():
    return _load_json(TICKETS_FILE)["tickets"]


def load_devops_teams():
    return _load_json(TEAMS_FILE)["teams"]


def seed_admin_users():
    for entry in load_admins():
        admin = User.query.filter_by(email=entry["email"]).first()
        password = _resolve_password(entry)

        if admin is None:
            admin = User(
                username=entry["username"],
                email=entry["email"],
                is_admin=True,
            )
            admin.set_password(password)
            db.session.add(admin)
        else:
            admin.is_admin = True
            if admin.username != entry["username"]:
                admin.username = entry["username"]

    db.session.commit()


def seed_admin_user():
    """Backwards-compatible alias used by tests and docs."""
    seed_admin_users()


def seed_devops_retros():
    admin = User.query.filter_by(email=ADMIN_EMAIL).first()
    if admin is None:
        return

    for retro_data in load_devops_retros():
        existing = Retro.query.filter_by(title=retro_data["title"]).first()
        if existing is not None:
            continue

        retro = Retro(
            title=retro_data["title"],
            description=retro_data.get("description"),
            created_by=admin.id,
            share_token=retro_data.get("share_token") or uuid.uuid4().hex,
            status="open",
        )
        db.session.add(retro)
        db.session.flush()

        db.session.add(
            RetroParticipant(retro_id=retro.id, user_id=admin.id)
        )

        for card_data in retro_data.get("cards", []):
            author = User.query.filter_by(username=card_data["author"]).first()
            if author is None:
                author = admin

            db.session.add(
                RetroCard(
                    retro_id=retro.id,
                    category=card_data["category"],
                    content=card_data["content"],
                    author_id=author.id,
                )
            )

    db.session.commit()


def _user_by_username(username):
    if not username:
        return None
    return User.query.filter_by(username=username).first()


def seed_devops_teams():
    admin = User.query.filter_by(email=ADMIN_EMAIL).first()
    if admin is None:
        return {}

    team_by_key = {}
    for team_data in load_devops_teams():
        project_key = team_data["project_key"]
        team = Team.query.filter_by(project_key=project_key).first()
        if team is None:
            owner = _user_by_username(team_data.get("owner")) or admin
            team = Team(
                name=team_data["name"],
                description=team_data.get("description"),
                project_key=project_key,
                created_by=owner.id,
            )
            db.session.add(team)
            db.session.flush()

        team_by_key[project_key] = team

        member_usernames = team_data.get("members", [])
        if team_data.get("owner") and team_data["owner"] not in member_usernames:
            member_usernames = [team_data["owner"]] + member_usernames

        for username in member_usernames:
            user = _user_by_username(username)
            if user is None:
                continue
            role = "owner" if username == team_data.get("owner") else "member"
            existing = TeamMember.query.filter_by(
                team_id=team.id, user_id=user.id
            ).first()
            if existing is None:
                db.session.add(
                    TeamMember(team_id=team.id, user_id=user.id, role=role)
                )
            elif role == "owner" and existing.role != "owner":
                existing.role = "owner"

    db.session.commit()
    return team_by_key


def seed_devops_tickets(team_by_key=None):
    admin = User.query.filter_by(email=ADMIN_EMAIL).first()
    if admin is None:
        return

    dev_team = None
    if team_by_key:
        dev_team = team_by_key.get("DEV")
    if dev_team is None:
        dev_team = Team.query.filter_by(project_key="DEV").first()
    if dev_team is None:
        return

    for ticket_data in load_devops_tickets():
        existing = Ticket.query.filter_by(
            team_id=dev_team.id,
            ticket_number=ticket_data["ticket_number"],
        ).first()
        if existing is not None:
            continue

        reporter = _user_by_username(ticket_data.get("reporter")) or admin
        assignee = _user_by_username(ticket_data.get("assignee"))

        ticket = Ticket(
            team_id=dev_team.id,
            ticket_number=ticket_data["ticket_number"],
            title=ticket_data["title"],
            description=ticket_data.get("description"),
            status=ticket_data.get("status", "todo"),
            priority=ticket_data.get("priority", "medium"),
            issue_type=ticket_data.get("issue_type", "task"),
            reporter_id=reporter.id,
            assignee_id=assignee.id if assignee else None,
        )
        db.session.add(ticket)
        db.session.flush()

        for comment_data in ticket_data.get("comments", []):
            author = _user_by_username(comment_data.get("author")) or admin
            db.session.add(
                TicketComment(
                    ticket_id=ticket.id,
                    user_id=author.id,
                    content=comment_data["content"],
                )
            )

        for subtask_data in ticket_data.get("subtasks", []):
            sub_assignee = _user_by_username(subtask_data.get("assignee"))
            subtask = Subtask(
                ticket_id=ticket.id,
                title=subtask_data["title"],
                description=subtask_data.get("description"),
                status=subtask_data.get("status", "todo"),
                assignee_id=sub_assignee.id if sub_assignee else None,
            )
            db.session.add(subtask)
            db.session.flush()

            for comment_data in subtask_data.get("comments", []):
                author = _user_by_username(comment_data.get("author")) or admin
                db.session.add(
                    TicketComment(
                        ticket_id=ticket.id,
                        subtask_id=subtask.id,
                        user_id=author.id,
                        content=comment_data["content"],
                    )
                )

    db.session.commit()


def backfill_ticket_teams():
    default_team = Team.query.filter_by(project_key="DEV").first()
    if default_team is None:
        return

    updated = (
        Ticket.query.filter(Ticket.team_id.is_(None))
        .update({Ticket.team_id: default_team.id}, synchronize_session=False)
    )
    if updated:
        db.session.commit()


def ensure_schema():
    """Add columns introduced after first deploy (create_all won't alter tables)."""
    inspector = inspect(db.engine)
    user_cols = {c["name"] for c in inspector.get_columns("user")}
    retro_cols = {c["name"] for c in inspector.get_columns("retro")}
    ticket_cols = {c["name"] for c in inspector.get_columns("ticket")} if "ticket" in inspector.get_table_names() else set()

    if "is_guest" not in user_cols:
        db.session.execute(
            text('ALTER TABLE "user" ADD COLUMN is_guest BOOLEAN DEFAULT FALSE NOT NULL')
        )
    if "display_name" not in user_cols:
        db.session.execute(
            text('ALTER TABLE "user" ADD COLUMN display_name VARCHAR(80)')
        )
    if "share_token" not in retro_cols:
        db.session.execute(
            text("ALTER TABLE retro ADD COLUMN share_token VARCHAR(32)")
        )
        db.session.execute(
            text("CREATE UNIQUE INDEX IF NOT EXISTS ix_retro_share_token ON retro (share_token)")
        )
    if ticket_cols and "team_id" not in ticket_cols:
        db.session.execute(
            text("ALTER TABLE ticket ADD COLUMN team_id INTEGER REFERENCES team(id)")
        )
    if ticket_cols or "ticket" in inspector.get_table_names():
        db.session.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS uq_team_ticket_number ON ticket (team_id, ticket_number)"
            )
        )

    db.session.commit()

    for retro in Retro.query.filter(
        (Retro.share_token.is_(None)) | (Retro.share_token == "")
    ).all():
        retro.share_token = uuid.uuid4().hex
    db.session.commit()
